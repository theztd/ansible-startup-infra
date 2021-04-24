job "promtail" {
  datacenters = ["de1", "dc1"]
  # Runs on all nomad clients
  type = "system"
  namespace = "system"

  group "promtail" {
    count = 1

    network {
      dns {
        servers = ["172.17.0.1", "8.8.8.8", "8.8.4.4"]
      }
      port "http" {
        static = 3200
      }
    }

    restart {
      attempts = 3
      delay    = "20s"
      mode     = "delay"
    }

    task "promtail" {
      driver = "docker"

      env {
        HOSTNAME = "${attr.unique.hostname}"
      }
      template {
        data        = <<EOTC
positions:
  filename: /data/positions.yaml

clients:
  - url: http://loki.fejk.net/loki/api/v1/push

scrape_configs:
- job_name: system
   pipeline_stages:
   static_configs:
   - labels:
      job: msglog
      env: nomad-devel
      __path__: /var/log/messages.log

- job_name: 'nomad-logs'
  consul_sd_configs:
    - server: '172.17.0.1:8500'
  relabel_configs:
    - source_labels: [__meta_consul_node]
      target_label: __host__
    - source_labels: [__meta_consul_service_metadata_external_source]
      target_label: source
      regex: (.*)
      replacement: '$1'
    - source_labels: [__meta_consul_service_id]
      regex: '_nomad-task-(.*)-(.*)-(.*)-(.*)'
      target_label:  'task_id'
      replacement: '$1'
    - source_labels: [__meta_consul_tags]
      regex: ',(app|monitoring),'
      target_label:  'group'
      replacement:   '$1'
    - source_labels: [__meta_consul_service]
      target_label: job
    - source_labels: ['__meta_consul_node']
      regex:         '(.*)'
      target_label:  'instance'
      replacement:   '$1'
    - source_labels: [__meta_consul_service_id]
      regex: '_nomad-task-(.*)-(.*)-(.*)-(.*)'
      target_label:  '__path__'
      replacement: '/nomad/alloc/$1/alloc/logs/*std*.{?,??}'
EOTC
        destination = "/local/promtail.yml"
      }

      config {
        image = "grafana/promtail"
        ports = ["http"]
        args = [
          "-config.file=/local/promtail.yml",
          "-server.http-listen-port=${NOMAD_PORT_http}",
        ]
        volumes = [
          "/data/promtail:/data",
          "/opt/nomad/data/:/nomad/"
        ]

        mount {
            type = "bind"
            source = "/var/log"
            target = "/local_logs/"
            readonly = true
        } 
      }

      resources {
        cpu    = 50
        memory = 100
      }

      service {
        name = "promtail"
        port = "http"
        tags = ["monitoring"]

        check {
          name     = "Promtail HTTP"
          type     = "http"
          path     = "/targets"
          interval = "5s"
          timeout  = "2s"

          check_restart {
            limit           = 2
            grace           = "60s"
            ignore_warnings = false
          }
        }
      }
    }
  }
}
