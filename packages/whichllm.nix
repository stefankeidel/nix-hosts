{ pkgs }:
let
  python = pkgs.python313;

  dbgpu = python.pkgs.buildPythonPackage rec {
    pname = "dbgpu";
    version = "2025.12";
    format = "setuptools";

    src = pkgs.fetchPypi {
      inherit pname version;
      hash = "sha256-1KL9w2/1/yrzfo/Yo+B0CrKvc8xeD9oZn9/z1vFob04=";
    };

    propagatedBuildInputs = with python.pkgs; [
      click
      pydantic
      thefuzz
    ];

    pythonImportsCheck = [ "dbgpu" ];

    meta = with pkgs.lib; {
      description = "Small open source database of GPU specifications";
      homepage = "https://github.com/painebenjamin/dbgpu";
      license = licenses.mit;
    };
  };
in
python.pkgs.buildPythonApplication rec {
  pname = "whichllm";
  version = "0.5.2";
  pyproject = true;

  src = pkgs.fetchFromGitHub {
    owner = "Andyyyy64";
    repo = "whichllm";
    rev = "2a566d3def99255875db32d4152eda7bb2602943";
    hash = "sha256-nyOCO1KN57e1Vhm2YwOTC+Z+RM7XAf5cG6wLvLTB/yM=";
  };

  build-system = with python.pkgs; [
    hatchling
  ];

  dependencies = with python.pkgs; [
    dbgpu
    httpx
    nvidia-ml-py
    psutil
    rich
    typer
  ];

  pythonImportsCheck = [ "whichllm" ];

  meta = with pkgs.lib; {
    description = "Find the best LLM that runs on your hardware";
    homepage = "https://github.com/Andyyyy64/whichllm";
    license = licenses.mit;
    mainProgram = "whichllm";
  };
}
