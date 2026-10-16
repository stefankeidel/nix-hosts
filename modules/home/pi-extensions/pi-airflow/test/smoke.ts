import { AirflowClient } from "../client.ts";

// Opt-in only: real vault access and production READS. Never print credentials or log contents.
if (process.env.PI_AIRFLOW_LIVE_TEST !== "1") {
  console.error("Live test is opt-in. Run PI_AIRFLOW_LIVE_TEST=1 npm run smoke with an existing az login and private-network access.");
  process.exitCode = 1;
} else {
  const client = new AirflowClient();
  try {
    const status = await client.enable();
    console.log(JSON.stringify({ check: "enable", version: status.version, ok: true }));
    const dags = await client.read({ operation: "dags", limit: 1 });
    console.log(JSON.stringify({ check: "list_dags", returned: dags.items.length, ok: true }));
    const dagId = process.env.PI_AIRFLOW_TEST_DAG ?? dags.items[0]?.dag_id;
    if (!dagId) {
      console.log("No visible DAGs; run/task/log checks skipped.");
    } else {
      const runs = await client.read({ operation: "runs", dagId, limit: 1 });
      console.log(JSON.stringify({ check: "list_runs", returned: runs.items.length, ok: true }));
      const dagRunId = runs.items[0]?.dag_run_id;
      if (!dagRunId) console.log("No DAG runs; task/log checks skipped.");
      else {
        await client.read({ operation: "run", dagId, dagRunId });
        console.log(JSON.stringify({ check: "get_run", ok: true }));
        const tasks = await client.read({ operation: "tasks", dagId, dagRunId, limit: 100 });
        console.log(JSON.stringify({ check: "list_tasks", returned: tasks.items.length, ok: true }));
        const task = tasks.items.find((item: any) => item.try_number > 0);
        if (!task) console.log("No attempted task in this page; log check skipped.");
        else {
          const logs = await client.read({ operation: "logs", dagId, dagRunId, taskId: task.task_id, tryNumber: task.try_number, mapIndex: task.map_index, maxChars: 500 });
          console.log(JSON.stringify({ check: "get_logs", returnedCharacters: logs.content.length, ok: true }));
        }
      }
    }
  } catch (error) {
    // Client errors omit response bodies and raw Azure/network diagnostics.
    console.error(error instanceof Error ? error.message : "Airflow live test failed.");
    process.exitCode = 1;
  } finally {
    client.dispose();
  }
}
