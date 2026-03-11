################################################################################
# Module: monitoring
# Installs via Helm:
#   - kube-prometheus-stack  (Prometheus + Grafana + Alertmanager)
#   - loki-stack             (Loki log aggregation)
#   - opentelemetry-collector
#   - prometheus-blackbox-exporter
# Also creates:
#   - SRE Golden Signals Grafana dashboard ConfigMap
#   - PrometheusRule for HTTP availability SLO
################################################################################

terraform {
  required_providers {
    null = { source = "hashicorp/null", version = "~> 3.0" }
  }
}

################################################################################
# 1 — Add Helm repos
################################################################################

resource "null_resource" "helm_repos" {
  triggers = { container_id = var.container_id }

  provisioner "remote-exec" {
    inline = [
      "helm repo add prometheus-community https://prometheus-community.github.io/helm-charts",
      "helm repo add grafana              https://grafana.github.io/helm-charts",
      "helm repo add open-telemetry       https://open-telemetry.github.io/opentelemetry-helm-charts",
      "helm repo update",
    ]
    connection {
      type = "docker"
      host = var.container_id
    }
  }
}

################################################################################
# 2 — monitoring namespace
################################################################################

resource "null_resource" "monitoring_ns" {
  triggers = { container_id = var.container_id }

  provisioner "remote-exec" {
    inline = [
      "kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -",
    ]
    connection {
      type = "docker"
      host = var.container_id
    }
  }

  depends_on = [null_resource.helm_repos]
}

################################################################################
# 3 — kube-prometheus-stack  (Prometheus + Grafana + Alertmanager)
################################################################################

resource "null_resource" "prometheus_stack" {
  triggers = { container_id = var.container_id }

  provisioner "remote-exec" {
    inline = [
      "helm upgrade --install prometheus prometheus-community/kube-prometheus-stack --namespace monitoring --wait --timeout 10m",
    ]
    connection {
      type = "docker"
      host = var.container_id
    }
  }

  depends_on = [null_resource.monitoring_ns]
}

################################################################################
# 4 — Loki stack (log aggregation)
################################################################################

resource "null_resource" "loki" {
  triggers = { container_id = var.container_id }

  provisioner "remote-exec" {
    inline = [
      "helm upgrade --install loki grafana/loki-stack --namespace monitoring --set grafana.enabled=false --wait --timeout 5m",
    ]
    connection {
      type = "docker"
      host = var.container_id
    }
  }

  depends_on = [null_resource.prometheus_stack]
}

################################################################################
# 5 — OpenTelemetry Collector
################################################################################

resource "null_resource" "otel" {
  triggers = { container_id = var.container_id }

  provisioner "remote-exec" {
    inline = [
      "helm upgrade --install otel open-telemetry/opentelemetry-collector --namespace monitoring --wait --timeout 5m",
    ]
    connection {
      type = "docker"
      host = var.container_id
    }
  }

  depends_on = [null_resource.loki]
}

################################################################################
# 6 — Blackbox Exporter  (probe external endpoints)
################################################################################

resource "null_resource" "blackbox" {
  triggers = { container_id = var.container_id }

  provisioner "remote-exec" {
    inline = [
      "helm upgrade --install blackbox prometheus-community/prometheus-blackbox-exporter --namespace monitoring --wait --timeout 5m",
    ]
    connection {
      type = "docker"
      host = var.container_id
    }
  }

  depends_on = [null_resource.otel]
}

################################################################################
# 7 — SRE Golden Signals Grafana dashboard (ConfigMap)
################################################################################

resource "null_resource" "grafana_dashboard" {
  triggers = { container_id = var.container_id }

  provisioner "remote-exec" {
    inline = [
      <<-SCRIPT
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: sre-golden-signals-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  golden-signals.json: |
    {
      "title": "SRE Golden Signals",
      "uid": "golden-signals",
      "schemaVersion": 38,
      "panels": [
        {
          "id": 1,
          "type": "timeseries",
          "title": "Latency (p99) — request duration",
          "gridPos": {"x":0,"y":0,"w":12,"h":8},
          "targets": [{
            "expr": "histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))",
            "legendFormat": "p99 latency"
          }]
        },
        {
          "id": 2,
          "type": "timeseries",
          "title": "Traffic — requests per second",
          "gridPos": {"x":12,"y":0,"w":12,"h":8},
          "targets": [{
            "expr": "sum(rate(http_requests_total[5m]))",
            "legendFormat": "req/s"
          }]
        },
        {
          "id": 3,
          "type": "timeseries",
          "title": "Errors — 5xx rate",
          "gridPos": {"x":0,"y":8,"w":12,"h":8},
          "targets": [{
            "expr": "sum(rate(http_requests_total{status=~\"5..\"}[5m])) / sum(rate(http_requests_total[5m]))",
            "legendFormat": "error rate"
          }]
        },
        {
          "id": 4,
          "type": "timeseries",
          "title": "Saturation — CPU usage",
          "gridPos": {"x":12,"y":8,"w":12,"h":8},
          "targets": [{
            "expr": "1 - avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m]))",
            "legendFormat": "CPU saturation"
          }]
        }
      ]
    }
EOF
SCRIPT
    ]
    connection {
      type = "docker"
      host = var.container_id
    }
  }

  depends_on = [null_resource.blackbox]
}

################################################################################
# 8 — PrometheusRule: HTTP availability SLO (99.9 % target)
################################################################################

resource "null_resource" "slo_rule" {
  triggers = { container_id = var.container_id }

  provisioner "remote-exec" {
    inline = [
      <<-SCRIPT
kubectl apply -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: sre-http-availability-slo
  namespace: monitoring
  labels:
    prometheus: kube-prometheus
    role: alert-rules
spec:
  groups:
  - name: slo.availability
    rules:
    # Rolling availability ratio (5-minute window)
    - record: job:http_request:availability
      expr: |
        sum(rate(http_requests_total{status!~"5.."}[5m]))
        /
        sum(rate(http_requests_total[5m]))

    # Alert when availability drops below 99.9 %
    - alert: HighErrorRate
      expr: job:http_request:availability < 0.999
      for: 2m
      labels:
        severity: critical
      annotations:
        summary: "HTTP availability SLO breach"
        description: "Availability {{ $value | humanizePercentage }} is below 99.9% SLO target."
EOF
SCRIPT
    ]
    connection {
      type = "docker"
      host = var.container_id
    }
  }

  depends_on = [null_resource.grafana_dashboard]
}
