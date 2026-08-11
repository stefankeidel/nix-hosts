{ ... }:
{
  virtualisation.oci-containers.containers.actual = {
    image = "actualbudget/actual-server:26.8.1";

    ports = [
      "127.0.0.1:5006:5006"
    ];

    volumes = [
      "/var/lib/actualbudget:/data"
    ];
  };

  services.nginx.virtualHosts."budget.keidel.me" = {
    forceSSL = true;
    enableACME = true;

    locations."= /internal/authelia/authz" = {
      proxyPass = "http://127.0.0.1:9091/api/authz/auth-request";
      extraConfig = ''
        internal;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_set_header Connection "";
        proxy_set_header X-Original-Method $request_method;
        proxy_set_header X-Original-URL $scheme://$host$request_uri;
        proxy_set_header X-Forwarded-For $remote_addr;
      '';
    };

    locations."/" = {
      proxyPass = "http://127.0.0.1:5006";
      proxyWebsockets = true;
      extraConfig = ''
        auth_request /internal/authelia/authz;
        auth_request_set $user $upstream_http_remote_user;
        auth_request_set $groups $upstream_http_remote_groups;
        auth_request_set $name $upstream_http_remote_name;
        auth_request_set $email $upstream_http_remote_email;
        auth_request_set $redirection_url $upstream_http_location;
        error_page 401 =302 $redirection_url;

        proxy_set_header Host $host;
        proxy_set_header Remote-User $user;
        proxy_set_header Remote-Groups $groups;
        proxy_set_header Remote-Name $name;
        proxy_set_header Remote-Email $email;
        proxy_set_header X-Original-URL $scheme://$host$request_uri;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-URI $request_uri;
      '';
    };
  };
}
