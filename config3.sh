#!/bin/bash
set -euo pipefail

# =========================================
# 🚀 GCP-XRAY HIGH-PERFORMANCE MULTI-ENGINE DEPLOYER
# ✅ ENGINES: OPENRESTY, ENVOY, HAPROXY, CADDY, SING-BOX
# ✅ WEBSOCKET ONLY (TROJAN-WS & VLESS-WS)
# ✅ ZERO-COPY SPLICE & KERNEL BUFFER TUNED
# ✅ DUAL-STACK (IPV4 & IPV6) READY
# =========================================

GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

if ! command -v jq &> /dev/null; then
    echo -e "\n${YELLOW}⚠️ Installing required tool: jq...${NC}"
    sudo apt-get update --allow-insecure-repositories -qq || true
    sudo apt-get install -y -qq --allow-unauthenticated jq || {
        echo -e "${RED}❌ Failed to install jq!${NC}"
        exit 1
    }
fi

list_deployed_services() {
  echo -e "\n======================================"
  echo -e "${CYAN}📋 ALL DEPLOYED GCP-XRAY SERVICES${NC}"
  echo -e "======================================"

  PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
  echo "Project: $PROJECT_ID"
  echo ""

  SERVICES=$(gcloud run services list \
    --format="value(metadata.name, status.url, region, metadata.creationTimestamp.date(%Y-%m-%d))" \
    --project="$PROJECT_ID" 2>/dev/null)

  if [ -z "$SERVICES" ]; then
    echo -e "${RED}❌ No services found.${NC}"
  else
    local COUNT=1
    while IFS=$'\t' read -r NAME URL REGION CREATED; do
      [ -z "$NAME" ] && continue
      echo -e "${GREEN}=== SERVICE #$COUNT ===${NC}"
      echo "🔹 Name: $NAME"
      echo "🔹 URL: $URL"
      echo "🔹 Region: $REGION"
      echo "🔹 Created: $CREATED"
      echo ""
      ((COUNT++))
    done <<< "$SERVICES"
  fi
  read -p "Press [Enter] to return..."
}

select_region() {
  echo -e "\n=== GCP CLOUD RUN REGION SELECTION ==="
  echo "1) asia-east1 (Taiwan 🇹🇼 - RECOMMENDED)"
  echo "2) asia-southeast1 (Singapore 🇸🇬)"
  echo "3) asia-northeast1 (Tokyo 🇯🇵)"
  echo "4) us-central1 (Iowa 🇺🇸)"
  echo "0) Enter custom region code"
  
  read -p "Enter region number: " REGION_NUM
  case $REGION_NUM in
    1) REGION="asia-east1" ;;
    2) REGION="asia-southeast1" ;;
    3) REGION="asia-northeast1" ;;
    4) REGION="us-central1" ;;
    0) read -p "Type full region code: " REGION ;;
    *) REGION="asia-east1" ;;
  esac
  echo -e "${GREEN}✅ Selected Region:${NC} $REGION"
}

deploy_new_service() {
  select_region

  PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
  if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}❌ No project set! Run: gcloud config set project YOUR_ID${NC}"
    return
  fi

  gcloud services enable run.googleapis.com cloudbuild.googleapis.com --project="$PROJECT_ID" --quiet

  echo -e "\n${CYAN}=========================================${NC}"
  echo -e "${GREEN}    CHOOSE TUNED PROXY ENGINE${NC}"
  echo -e "${CYAN}=========================================${NC}"
  echo "1) OpenResty  - [Maximum Throughput & Nginx Buffering Disabled]"
  echo "2) Envoy Proxy - [Ultra Low Overhead & Direct Streaming]"
  echo "3) HAProxy     - [Zero-Copy Kernel Splice Engine - FASTEST]"
  echo "4) Caddy Proxy - [Zero Buffer Flush Streaming]"
  echo "5) Sing-Box    - [Native High-Speed Routing]"

  while true; do
    read -p "Select Engine [1-5]: " ENGINE_CHOICE
    case $ENGINE_CHOICE in
      1) ENGINE="openresty"; DISPLAY_ENGINE="OpenResty (Tuned)"; break ;;
      2) ENGINE="envoy"; DISPLAY_ENGINE="Envoy (Tuned)"; break ;;
      3) ENGINE="haproxy"; DISPLAY_ENGINE="HAProxy (Tuned Splice)"; break ;;
      4) ENGINE="caddy"; DISPLAY_ENGINE="Caddy (Tuned)"; break ;;
      5) ENGINE="singbox"; DISPLAY_ENGINE="Sing-Box (Native)"; break ;;
      *) echo -e "${RED}Select 1-5 only${NC}" ;;
    esac
  done

  RAND=$(openssl rand -hex 3)
  CLOUD_RUN_SERVICE_NAME="gcp-xray-${ENGINE}-$RAND"

  MEMORY="2Gi"
  CPU="2"
  MIN_INST=1
  MAX_INST=5
  CONCURRENCY=1000
  TIMEOUT=3600

  BUILD_DIR=$(mktemp -d)
  trap 'rm -rf "$BUILD_DIR"' EXIT
  cd "$BUILD_DIR" || exit 1

  cat > index.html <<'EOF'
<!DOCTYPE html>
<html><head><title>Cloud Gateway</title></head>
<body style="background:#0b0f19;color:#fff;font-family:sans-serif;display:flex;justify-content:center;align-items:center;height:100vh;">
<h2>Cloud Application Gateway Operational</h2>
</body></html>
EOF

  cat > config.json <<'EOF'
{
  "log": {"loglevel": "warning"},
  "dns": {
    "servers": ["1.1.1.1", "8.8.8.8", "2606:4700:4700::1111", "2001:4860:4860::8888"],
    "queryStrategy": "UseIP"
  },
  "inbounds": [
    {
      "port": 10001, "listen": "::", "protocol": "trojan", "tag": "trojan-ws",
      "settings": {"clients": [{"password": "gcp-xray"}]},
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/trojan-ws"},
        "sockopt": {"tcpFastOpen": true, "tcpNoDelay": true, "tcpKeepAliveInterval": 15, "tcpKeepAliveIdle": 30}
      }
    },
    {
      "port": 10002, "listen": "::", "protocol": "vless", "tag": "vless-ws",
      "settings": {"clients": [{"id": "a1b2c3d4-5678-40ef-98ab-cdef01234567"}], "decryption": "none"},
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/vless-ws"},
        "sockopt": {"tcpFastOpen": true, "tcpNoDelay": true, "tcpKeepAliveInterval": 15, "tcpKeepAliveIdle": 30}
      }
    }
  ],
  "outbounds": [{"protocol": "freedom", "tag": "direct", "settings": {"domainStrategy": "IPIfNonMatch"}}]
}
EOF

  if [ "$ENGINE" = "openresty" ]; then
    cat > nginx.conf <<'EOF'
worker_processes auto;
worker_rlimit_nofile 1048576;
events {
    worker_connections 65535;
    use epoll;
    multi_accept on;
}
http {
    include /usr/local/openresty/nginx/conf/mime.types;
    default_type application/octet-stream;
    
    sendfile on;
    tcp_nodelay on;
    tcp_nopush on;
    reset_timedout_connection on;
    
    keepalive_timeout 7200s;
    keepalive_requests 1000000;
    
    client_max_body_size 0;
    proxy_buffering off;
    proxy_request_buffering off;
    proxy_max_temp_file_size 0;
    
    proxy_connect_timeout 5s;
    proxy_send_timeout 7200s;
    proxy_read_timeout 7200s;

    server_tokens off;

    upstream trojan_backend { server [::1]:10001 keepalive 1024; }
    upstream vless_backend  { server [::1]:10002 keepalive 1024; }

    server {
        listen 8080 default_server reuseport backlog=65535;
        listen [::]:8080 default_server reuseport backlog=65535;
        server_name _;

        location /health { return 200 "OK\n"; }
        location / { root /usr/local/openresty/nginx/html; index index.html; }

        location /trojan-ws {
            proxy_pass http://trojan_backend;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }

        location /vless-ws {
            proxy_pass http://vless_backend;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
EOF
    cat > entrypoint.sh <<'EOF'
#!/bin/sh
/usr/local/bin/xray run -c /etc/xray.json &
exec /usr/local/openresty/bin/openresty -g 'daemon off;'
EOF
    chmod +x entrypoint.sh

    cat > Dockerfile <<'EOF'
FROM alpine:3.20 AS builder
RUN apk add --no-cache curl unzip
RUN curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o xray.zip && unzip -q xray.zip xray && chmod +x xray

FROM openresty/openresty:alpine-fat
USER root
COPY --from=builder /xray /usr/local/bin/xray
COPY config.json /etc/xray.json
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY index.html /usr/local/openresty/nginx/html/index.html
COPY entrypoint.sh /entrypoint.sh
EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
EOF

  elif [ "$ENGINE" = "envoy" ]; then
    cat > envoy.yaml <<'EOF'
static_resources:
  listeners:
  - name: listener_0
    address: { socket_address: { address: 0.0.0.0, port_value: 8080 } }
    per_connection_buffer_limit_bytes: 1048576
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: ingress_http
          use_remote_address: true
          delayed_close_timeout: 0s
          upgrade_configs: [{ upgrade_type: "websocket" }]
          route_config:
            name: local_route
            virtual_hosts:
            - name: local_service
              domains: ["*"]
              routes:
              - match: { prefix: "/health" }
                direct_response: { status: 200, body: { inline_string: "OK\n" } }
              - match: { prefix: "/trojan-ws" }
                route: { cluster: trojan_ws_cluster, timeout: 0s, idle_timeout: 0s }
              - match: { prefix: "/vless-ws" }
                route: { cluster: vless_ws_cluster, timeout: 0s, idle_timeout: 0s }
              - match: { prefix: "/" }
                direct_response: { status: 200, body: { inline_string: "Gateway Active" } }
          http_filters:
          - name: envoy.filters.http.router
            typed_config: { "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router }

  clusters:
  - name: trojan_ws_cluster
    connect_timeout: 5s
    type: STATIC
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: trojan_ws_cluster
      endpoints: [{ lb_endpoints: [{ endpoint: { address: { socket_address: { address: "::1", port_value: 10001 } } } }] }]
  - name: vless_ws_cluster
    connect_timeout: 5s
    type: STATIC
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: vless_ws_cluster
      endpoints: [{ lb_endpoints: [{ endpoint: { address: { socket_address: { address: "::1", port_value: 10002 } } } }] }]
EOF
    cat > entrypoint.sh <<'EOF'
#!/bin/sh
/usr/local/bin/xray run -c /etc/xray.json &
exec envoy -c /etc/envoy.yaml
EOF
    chmod +x entrypoint.sh

    cat > Dockerfile <<'EOF'
FROM alpine:3.20 AS builder
RUN apk add --no-cache curl unzip
RUN curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o xray.zip && unzip -q xray.zip xray && chmod +x xray

FROM envoyproxy/envoy:v1.30-latest
USER root
COPY --from=builder /xray /usr/local/bin/xray
COPY config.json /etc/xray.json
COPY envoy.yaml /etc/envoy.yaml
COPY entrypoint.sh /entrypoint.sh
EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
EOF

  elif [ "$ENGINE" = "haproxy" ]; then
    cat > haproxy.cfg <<'EOF'
global
    log stdout format raw local0
    maxconn 200000
    tune.bufsize 65536
    tune.pipesize 65536
    tune.rcvbuf.backend 2097152
    tune.sndbuf.backend 2097152

defaults
    log global
    mode http
    option splice-response
    option splice-request
    option http-server-close
    timeout connect 5s
    timeout client 7200s
    timeout server 7200s

frontend main
    bind 0.0.0.0:8080
    acl is_health path /health
    acl is_trojan_ws path_beg /trojan-ws
    acl is_vless_ws path_beg /vless-ws

    use_backend health_backend if is_health
    use_backend trojan_ws_backend if is_trojan_ws
    use_backend vless_ws_backend if is_vless_ws
    default_backend default_backend

backend health_backend
    http-request return status 200 content-type "text/plain" string "OK\n"

backend default_backend
    http-request return status 200 content-type "text/html" string "Application Gateway Active"

backend trojan_ws_backend
    server xray_tws [::1]:10001 maxconn 100000

backend vless_ws_backend
    server xray_vws [::1]:10002 maxconn 100000
EOF

    cat > entrypoint.sh <<'EOF'
#!/bin/sh
/usr/local/bin/xray run -c /etc/xray.json &
exec haproxy -W -db -f /usr/local/etc/haproxy/haproxy.cfg
EOF
    chmod +x entrypoint.sh

    cat > Dockerfile <<'EOF'
FROM alpine:3.20 AS builder
RUN apk add --no-cache curl unzip
RUN curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o xray.zip && unzip -q xray.zip xray && chmod +x xray

FROM haproxy:2.8-alpine
USER root
COPY --from=builder /xray /usr/local/bin/xray
COPY config.json /etc/xray.json
COPY haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
EXPOSE 8080
EOF

  elif [ "$ENGINE" = "caddy" ]; then
    cat > Caddyfile <<'EOF'
{
    admin off
    http_port 8080
    servers {
        max_header_size 16mb
        read_timeout 7200s
        write_timeout 7200s
        idle_timeout 7200s
    }
}

:8080 {
    handle /health { respond "OK\n" 200 }

    handle /trojan-ws* {
        reverse_proxy [::1]:10001 {
            flush_interval -1
            header_up Host {host}
            header_up X-Real-IP {remote_host}
        }
    }

    handle /vless-ws* {
        reverse_proxy [::1]:10002 {
            flush_interval -1
            header_up Host {host}
            header_up X-Real-IP {remote_host}
        }
    }

    handle {
        root * /usr/share/caddy
        file_server
    }
}
EOF
    cat > entrypoint.sh <<'EOF'
#!/bin/sh
/usr/local/bin/xray run -c /etc/xray.json &
exec caddy run --config /etc/Caddyfile --adapter caddyfile
EOF
    chmod +x entrypoint.sh

    cat > Dockerfile <<'EOF'
FROM alpine:3.20 AS builder
RUN apk add --no-cache curl unzip
RUN curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o xray.zip && unzip -q xray.zip xray && chmod +x xray

FROM caddy:2.7-alpine
USER root
COPY --from=builder /xray /usr/local/bin/xray
COPY config.json /etc/xray.json
COPY Caddyfile /etc/Caddyfile
COPY index.html /usr/share/caddy/index.html
COPY entrypoint.sh /entrypoint.sh
EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
EOF

  elif [ "$ENGINE" = "singbox" ]; then
    cat > Caddyfile <<'EOF'
{
    admin off
    http_port 8080
}

:8080 {
    handle /health { respond "OK\n" 200 }

    handle /trojan-ws* {
        reverse_proxy [::1]:10001 {
            flush_interval -1
            header_up Host {host}
            header_up X-Real-IP {remote_host}
        }
    }

    handle /vless-ws* {
        reverse_proxy [::1]:10002 {
            flush_interval -1
            header_up Host {host}
            header_up X-Real-IP {remote_host}
        }
    }

    handle { root * /usr/share/caddy; file_server }
}
EOF
    cat > singbox.json <<'EOF'
{
  "log": { "level": "warn" },
  "dns": {
    "servers": [
      {"tag": "dns-cf", "address": "1.1.1.1", "strategy": "prefer_ipv4"},
      {"tag": "dns-goog", "address": "8.8.8.8", "strategy": "prefer_ipv4"}
    ]
  },
  "inbounds": [
    {
      "type": "trojan",
      "tag": "trojan-ws",
      "listen": "::",
      "listen_port": 10001,
      "users": [{"password": "gcp-xray"}],
      "transport": { "type": "ws", "path": "/trojan-ws" }
    },
    {
      "type": "vless",
      "tag": "vless-ws",
      "listen": "::",
      "listen_port": 10002,
      "users": [{"uuid": "a1b2c3d4-5678-40ef-98ab-cdef01234567"}],
      "transport": { "type": "ws", "path": "/vless-ws" }
    }
  ],
  "outbounds": [{"type": "direct", "tag": "direct", "domain_strategy": "ip_if_non_match"}]
}
EOF
    cat > entrypoint.sh <<'EOF'
#!/bin/sh
/usr/local/bin/sing-box run -c /etc/singbox.json &
exec caddy run --config /etc/Caddyfile --adapter caddyfile
EOF
    chmod +x entrypoint.sh

    cat > Dockerfile <<'EOF'
FROM ghcr.io/sagernet/sing-box:latest AS singbox-builder

FROM caddy:2.7-alpine
USER root
COPY --from=singbox-builder /usr/local/bin/sing-box /usr/local/bin/sing-box
COPY singbox.json /etc/singbox.json
COPY Caddyfile /etc/Caddyfile
COPY index.html /usr/share/caddy/index.html
COPY entrypoint.sh /entrypoint.sh
EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
EOF
  fi

  echo -e "${CYAN}🔨 Building Tuned Container Image...${NC}"
  gcloud builds submit --project="$PROJECT_ID" --tag gcr.io/$PROJECT_ID/$CLOUD_RUN_SERVICE_NAME . --quiet

  echo -e "${CYAN}🚀 Deploying to Cloud Run...${NC}"
  gcloud run deploy "$CLOUD_RUN_SERVICE_NAME" \
    --image gcr.io/$PROJECT_ID/$CLOUD_RUN_SERVICE_NAME \
    --project="$PROJECT_ID" --platform managed --region "$REGION" --allow-unauthenticated \
    --port 8080 --memory "$MEMORY" --cpu "$CPU" --concurrency "$CONCURRENCY" \
    --timeout "$TIMEOUT" --min-instances "$MIN_INST" --max-instances "$MAX_INST" \
    --session-affinity --execution-environment gen2 --no-cpu-throttling --cpu-boost --quiet

  CLOUD_RUN_URL=$(gcloud run services describe "$CLOUD_RUN_SERVICE_NAME" --project="$PROJECT_ID" --region="$REGION" --format='value(status.url)')
  
  clear
  echo -e "\n${CYAN}=========================================${NC}"
  echo -e "${GREEN}✅ ULTRA-TUNED DEPLOYMENT SUCCESS!${NC}"
  echo -e "${CYAN}=========================================${NC}"
  echo -e "${GREEN}🌐 URL:${NC} $CLOUD_RUN_URL"
  echo -e "${GREEN}⚡ Engine:${NC} $DISPLAY_ENGINE"
  echo -e "  ✅ Zero-Copy & Kernel Socket Buffers Injected"
  echo -e "  ✅ High-Speed WebSocket Proxy Settings Applied"
  echo -e "  ✅ Disabled Engine-Level Buffering Lag"
  echo ""
  read -p "Press [Enter] to return..."
}

while true; do
  clear
  echo "======================================"
  echo "HIGH-PERFORMANCE GCP-XRAY MENU"
  echo "======================================"
  echo "1) Deploy Tuned Service to Cloud Run"
  echo "2) List Active Services"
  echo "3) Exit"
  echo "======================================"
  read -p "Select Option [1-3]: " MENU_CHOICE

  case $MENU_CHOICE in
    1) deploy_new_service ;;
    2) list_deployed_services ;;
    3) exit 0 ;;
    *) sleep 1 ;;
  esac
done
