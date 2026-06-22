# Preserve state addresses after moving root resources into feature modules.
moved {
  from = aws_vpc.main
  to   = module.network.aws_vpc.main
}

moved {
  from = aws_internet_gateway.main
  to   = module.network.aws_internet_gateway.main
}

moved {
  from = aws_eip.nat
  to   = module.network.aws_eip.nat
}

moved {
  from = aws_nat_gateway.main
  to   = module.network.aws_nat_gateway.main
}

moved {
  from = aws_subnet.public
  to   = module.network.aws_subnet.public
}

moved {
  from = aws_subnet.private_app
  to   = module.network.aws_subnet.private_app
}

moved {
  from = aws_subnet.db
  to   = module.network.aws_subnet.db
}

moved {
  from = aws_route_table.public
  to   = module.network.aws_route_table.public
}

moved {
  from = aws_route_table_association.public
  to   = module.network.aws_route_table_association.public
}

moved {
  from = aws_route_table.private_app
  to   = module.network.aws_route_table.private_app
}

moved {
  from = aws_route_table_association.private_app
  to   = module.network.aws_route_table_association.private_app
}

moved {
  from = aws_route_table.db
  to   = module.network.aws_route_table.db
}

moved {
  from = aws_route_table_association.db
  to   = module.network.aws_route_table_association.db
}

moved {
  from = aws_security_group.alb
  to   = module.security.aws_security_group.alb
}

moved {
  from = aws_security_group.bastion
  to   = module.security.aws_security_group.bastion
}

moved {
  from = aws_security_group.app
  to   = module.security.aws_security_group.app
}

moved {
  from = aws_security_group.db
  to   = module.security.aws_security_group.db
}

moved {
  from = aws_security_group.master_node
  to   = module.security.aws_security_group.master_node
}

moved {
  from = aws_security_group_rule.bastion_ingress_ssh
  to   = module.security.aws_security_group_rule.bastion_ingress_ssh
}

moved {
  from = aws_security_group_rule.bastion_egress_all
  to   = module.security.aws_security_group_rule.bastion_egress_all
}

moved {
  from = aws_security_group_rule.app_ingress_ssh_from_bastion
  to   = module.security.aws_security_group_rule.app_ingress_ssh_from_bastion
}

moved {
  from = aws_security_group_rule.alb_ingress_http
  to   = module.security.aws_security_group_rule.alb_ingress_http
}

moved {
  from = aws_security_group_rule.alb_ingress_portainer
  to   = module.security.aws_security_group_rule.alb_ingress_portainer
}

moved {
  from = aws_security_group_rule.alb_egress_all
  to   = module.security.aws_security_group_rule.alb_egress_all
}

moved {
  from = aws_security_group_rule.app_ingress_http
  to   = module.security.aws_security_group_rule.app_ingress_http
}

moved {
  from = aws_security_group_rule.app_ingress_app_port
  to   = module.security.aws_security_group_rule.app_ingress_app_port
}

moved {
  from = aws_security_group_rule.app_egress_all
  to   = module.security.aws_security_group_rule.app_egress_all
}

moved {
  from = aws_security_group_rule.db_ingress_ssh_from_bastion
  to   = module.security.aws_security_group_rule.db_ingress_ssh_from_bastion
}

moved {
  from = aws_security_group_rule.db_ingress_postgres_self
  to   = module.security.aws_security_group_rule.db_ingress_postgres_self
}

moved {
  from = aws_security_group_rule.db_ingress_postgres
  to   = module.security.aws_security_group_rule.db_ingress_postgres
}

moved {
  from = aws_security_group_rule.db_egress_all
  to   = module.security.aws_security_group_rule.db_egress_all
}

moved {
  from = aws_security_group_rule.db_ingress_swarm_management_self
  to   = module.security.aws_security_group_rule.db_ingress_swarm_management_self
}

moved {
  from = aws_security_group_rule.db_ingress_swarm_gossip_tcp_self
  to   = module.security.aws_security_group_rule.db_ingress_swarm_gossip_tcp_self
}

moved {
  from = aws_security_group_rule.db_ingress_swarm_gossip_udp_self
  to   = module.security.aws_security_group_rule.db_ingress_swarm_gossip_udp_self
}

moved {
  from = aws_security_group_rule.db_ingress_swarm_overlay_self
  to   = module.security.aws_security_group_rule.db_ingress_swarm_overlay_self
}

moved {
  from = aws_security_group_rule.db_ingress_haproxy_stats_from_bastion
  to   = module.security.aws_security_group_rule.db_ingress_haproxy_stats_from_bastion
}

moved {
  from = aws_security_group_rule.master_ingress_ssh_from_bastion
  to   = module.security.aws_security_group_rule.master_ingress_ssh_from_bastion
}

moved {
  from = aws_security_group_rule.master_ingress_portainer_from_bastion
  to   = module.security.aws_security_group_rule.master_ingress_portainer_from_bastion
}

moved {
  from = aws_security_group_rule.master_ingress_portainer_from_alb
  to   = module.security.aws_security_group_rule.master_ingress_portainer_from_alb
}

moved {
  from = aws_security_group_rule.master_ingress_redis_from_workers
  to   = module.security.aws_security_group_rule.master_ingress_redis_from_workers
}

moved {
  from = aws_security_group_rule.master_ingress_swarm_management_from_workers
  to   = module.security.aws_security_group_rule.master_ingress_swarm_management_from_workers
}

moved {
  from = aws_security_group_rule.master_ingress_swarm_management_self
  to   = module.security.aws_security_group_rule.master_ingress_swarm_management_self
}

moved {
  from = aws_security_group_rule.master_ingress_swarm_gossip_tcp_from_workers
  to   = module.security.aws_security_group_rule.master_ingress_swarm_gossip_tcp_from_workers
}

moved {
  from = aws_security_group_rule.master_ingress_swarm_gossip_tcp_self
  to   = module.security.aws_security_group_rule.master_ingress_swarm_gossip_tcp_self
}

moved {
  from = aws_security_group_rule.master_ingress_swarm_gossip_udp_from_workers
  to   = module.security.aws_security_group_rule.master_ingress_swarm_gossip_udp_from_workers
}

moved {
  from = aws_security_group_rule.master_ingress_swarm_gossip_udp_self
  to   = module.security.aws_security_group_rule.master_ingress_swarm_gossip_udp_self
}

moved {
  from = aws_security_group_rule.master_ingress_swarm_overlay_from_workers
  to   = module.security.aws_security_group_rule.master_ingress_swarm_overlay_from_workers
}

moved {
  from = aws_security_group_rule.master_ingress_swarm_overlay_self
  to   = module.security.aws_security_group_rule.master_ingress_swarm_overlay_self
}

moved {
  from = aws_security_group_rule.master_egress_all
  to   = module.security.aws_security_group_rule.master_egress_all
}

moved {
  from = aws_security_group_rule.app_ingress_swarm_management_from_master
  to   = module.security.aws_security_group_rule.app_ingress_swarm_management_from_master
}

moved {
  from = aws_security_group_rule.app_ingress_swarm_management_self
  to   = module.security.aws_security_group_rule.app_ingress_swarm_management_self
}

moved {
  from = aws_security_group_rule.app_ingress_swarm_gossip_tcp_from_master
  to   = module.security.aws_security_group_rule.app_ingress_swarm_gossip_tcp_from_master
}

moved {
  from = aws_security_group_rule.app_ingress_swarm_gossip_tcp_self
  to   = module.security.aws_security_group_rule.app_ingress_swarm_gossip_tcp_self
}

moved {
  from = aws_security_group_rule.app_ingress_swarm_gossip_udp_from_master
  to   = module.security.aws_security_group_rule.app_ingress_swarm_gossip_udp_from_master
}

moved {
  from = aws_security_group_rule.app_ingress_swarm_gossip_udp_self
  to   = module.security.aws_security_group_rule.app_ingress_swarm_gossip_udp_self
}

moved {
  from = aws_security_group_rule.app_ingress_swarm_overlay_from_master
  to   = module.security.aws_security_group_rule.app_ingress_swarm_overlay_from_master
}

moved {
  from = aws_security_group_rule.app_ingress_swarm_overlay_self
  to   = module.security.aws_security_group_rule.app_ingress_swarm_overlay_self
}

moved {
  from = aws_security_group_rule.bastion_ingress_grafana_from_my_ip
  to   = module.security.aws_security_group_rule.bastion_ingress_grafana_from_my_ip
}

moved {
  from = aws_security_group_rule.bastion_ingress_prometheus_from_my_ip
  to   = module.security.aws_security_group_rule.bastion_ingress_prometheus_from_my_ip
}

moved {
  from = aws_security_group_rule.bastion_ingress_loki_from_app
  to   = module.security.aws_security_group_rule.bastion_ingress_loki_from_app
}

moved {
  from = aws_security_group_rule.app_ingress_node_exporter_from_bastion
  to   = module.security.aws_security_group_rule.app_ingress_node_exporter_from_bastion
}

moved {
  from = aws_security_group_rule.db_ingress_node_exporter_from_bastion
  to   = module.security.aws_security_group_rule.db_ingress_node_exporter_from_bastion
}

moved {
  from = aws_security_group_rule.db_ingress_cadvisor_from_bastion
  to   = module.security.aws_security_group_rule.db_ingress_cadvisor_from_bastion
}

moved {
  from = aws_security_group_rule.app_ingress_cadvisor_from_bastion
  to   = module.security.aws_security_group_rule.app_ingress_cadvisor_from_bastion
}

moved {
  from = aws_security_group_rule.master_ingress_redis_exporter_from_bastion
  to   = module.security.aws_security_group_rule.master_ingress_redis_exporter_from_bastion
}

moved {
  from = aws_iam_role.ec2_instance_role
  to   = module.iam.aws_iam_role.ec2_instance_role
}

moved {
  from = aws_iam_role_policy_attachment.ssm
  to   = module.iam.aws_iam_role_policy_attachment.ssm
}

moved {
  from = aws_iam_role_policy_attachment.ecr_readonly
  to   = module.iam.aws_iam_role_policy_attachment.ecr_readonly
}

moved {
  from = aws_iam_role_policy.swarm_ssm
  to   = module.iam.aws_iam_role_policy.swarm_ssm
}

moved {
  from = aws_iam_role_policy.backend_image_s3
  to   = module.iam.aws_iam_role_policy.backend_image_s3
}

moved {
  from = aws_iam_role_policy.ec2_self_tag
  to   = module.iam.aws_iam_role_policy.ec2_self_tag
}

moved {
  from = aws_iam_instance_profile.instance_profile
  to   = module.iam.aws_iam_instance_profile.instance_profile
}

moved {
  from = aws_iam_role_policy.prometheus_ec2_sd
  to   = module.iam.aws_iam_role_policy.prometheus_ec2_sd
}

moved {
  from = aws_iam_role_policy.queue_metrics
  to   = module.iam.aws_iam_role_policy.queue_metrics
}

moved {
  from = tls_private_key.app_key
  to   = module.access.tls_private_key.app_key
}

moved {
  from = aws_key_pair.app_key
  to   = module.access.aws_key_pair.app_key
}

moved {
  from = local_file.private_key
  to   = module.access.local_file.private_key
}

moved {
  from = aws_secretsmanager_secret.private_key
  to   = module.access.aws_secretsmanager_secret.private_key
}

moved {
  from = aws_secretsmanager_secret_version.private_key
  to   = module.access.aws_secretsmanager_secret_version.private_key
}

moved {
  from = aws_lb.application_load_balancer
  to   = module.alb.aws_lb.application_load_balancer
}

moved {
  from = aws_lb_target_group.app
  to   = module.alb.aws_lb_target_group.app
}

moved {
  from = aws_lb_target_group.backend
  to   = module.alb.aws_lb_target_group.backend
}

moved {
  from = aws_lb_listener.http
  to   = module.alb.aws_lb_listener.http
}

moved {
  from = aws_lb_target_group.portainer
  to   = module.alb.aws_lb_target_group.portainer
}

moved {
  from = aws_lb_target_group_attachment.portainer_master
  to   = module.alb.aws_lb_target_group_attachment.portainer_master
}

moved {
  from = aws_lb_listener.portainer
  to   = module.alb.aws_lb_listener.portainer
}

moved {
  from = aws_launch_template.app_lt
  to   = module.app.aws_launch_template.app_lt
}

moved {
  from = aws_autoscaling_group.app_asg
  to   = module.app.aws_autoscaling_group.app_asg
}

moved {
  from = aws_autoscaling_policy.cpu_target_tracking
  to   = module.app.aws_autoscaling_policy.cpu_target_tracking
}

moved {
  from = aws_autoscaling_policy.queue_target_tracking
  to   = module.app.aws_autoscaling_policy.queue_target_tracking
}

moved {
  from = aws_autoscaling_policy.queue_burst_step_scale_out
  to   = module.app.aws_autoscaling_policy.queue_burst_step_scale_out
}

moved {
  from = aws_cloudwatch_metric_alarm.queue_burst_scale_out
  to   = module.app.aws_cloudwatch_metric_alarm.queue_burst_scale_out
}

moved {
  from = aws_ssm_document.queue_metric_publisher
  to   = module.app.aws_ssm_document.queue_metric_publisher
}

moved {
  from = aws_ssm_association.queue_metric_publisher
  to   = module.app.aws_ssm_association.queue_metric_publisher
}

moved {
  from = aws_ssm_document.queue_consumer
  to   = module.app.aws_ssm_document.queue_consumer
}

moved {
  from = aws_ssm_association.queue_consumer
  to   = module.app.aws_ssm_association.queue_consumer
}

moved {
  from = aws_instance.master_node
  to   = module.swarm_master.aws_instance.master_node
}

moved {
  from = aws_ec2_instance_state.master_node
  to   = module.swarm_master.aws_ec2_instance_state.master_node
}

moved {
  from = aws_instance.bastion
  to   = module.bastion_monitoring.aws_instance.bastion
}

moved {
  from = aws_ec2_instance_state.bastion
  to   = module.bastion_monitoring.aws_ec2_instance_state.bastion
}

moved {
  from = aws_instance.db_main
  to   = module.postgres_ha.aws_instance.db_main
}

moved {
  from = aws_instance.postgres_primary
  to   = module.postgres_ha.aws_instance.postgres_primary
}

moved {
  from = aws_instance.postgres_replica1
  to   = module.postgres_ha.aws_instance.postgres_replica1
}

moved {
  from = aws_instance.postgres_replica2
  to   = module.postgres_ha.aws_instance.postgres_replica2
}

moved {
  from = aws_ssm_parameter.db_host
  to   = module.postgres_ha.aws_ssm_parameter.db_host
}

moved {
  from = aws_ssm_parameter.db_port
  to   = module.postgres_ha.aws_ssm_parameter.db_port
}

moved {
  from = aws_ssm_parameter.db_name
  to   = module.postgres_ha.aws_ssm_parameter.db_name
}

moved {
  from = aws_ssm_parameter.db_user
  to   = module.postgres_ha.aws_ssm_parameter.db_user
}

moved {
  from = aws_ssm_parameter.db_password
  to   = module.postgres_ha.aws_ssm_parameter.db_password
}

moved {
  from = aws_ec2_instance_state.db_main
  to   = module.postgres_ha.aws_ec2_instance_state.db_main
}

moved {
  from = aws_ec2_instance_state.postgres_primary
  to   = module.postgres_ha.aws_ec2_instance_state.postgres_primary
}

moved {
  from = aws_ec2_instance_state.postgres_replica1
  to   = module.postgres_ha.aws_ec2_instance_state.postgres_replica1
}

moved {
  from = aws_ec2_instance_state.postgres_replica2
  to   = module.postgres_ha.aws_ec2_instance_state.postgres_replica2
}

moved {
  from = aws_iam_role.asg_notify_lambda_role
  to   = module.notification.aws_iam_role.asg_notify_lambda_role
}

moved {
  from = aws_iam_role_policy_attachment.asg_notify_lambda_basic
  to   = module.notification.aws_iam_role_policy_attachment.asg_notify_lambda_basic
}

moved {
  from = aws_lambda_function.asg_notify
  to   = module.notification.aws_lambda_function.asg_notify
}

moved {
  from = aws_cloudwatch_event_rule.asg_events
  to   = module.notification.aws_cloudwatch_event_rule.asg_events
}

moved {
  from = aws_cloudwatch_event_target.asg_events_to_lambda
  to   = module.notification.aws_cloudwatch_event_target.asg_events_to_lambda
}

moved {
  from = aws_lambda_permission.allow_eventbridge_asg
  to   = module.notification.aws_lambda_permission.allow_eventbridge_asg
}

