{ ... }:

{
  services.nginx.virtualHosts."music.keidel.me" = {
    forceSSL = true;
    enableACME = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:4533";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
      '';
    };
  };

  services.nginx.virtualHosts."images.keidel.me" = {
    forceSSL = true;
    enableACME = true;
    extraConfig = ''
      # allow large file uploads
      client_max_body_size 50000M;

      # disable buffering uploads to prevent OOM on reverse proxy server and make uploads twice as fast (no pause)
      proxy_request_buffering off;

      # increase body buffer to avoid limiting upload speed
      client_body_buffer_size 1024k;

      # Set headers
      proxy_set_header Host              $host;
      proxy_set_header X-Real-IP         $remote_addr;
      proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;

      # enable websockets: http://nginx.org/en/docs/http/websocket.html
      proxy_http_version 1.1;
      proxy_redirect     off;

      # set timeout
      proxy_read_timeout 600s;
      proxy_send_timeout 600s;
      send_timeout       600s;
    '';

    locations."/" = {
      proxyPass = "http://127.0.0.1:2283";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header   Upgrade    $http_upgrade;
        proxy_set_header   Connection "upgrade";
      '';
    };
  };
}
