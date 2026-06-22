module "network" {
  source = "./modules/network"

  name_prefix              = local.name_prefix
  env                      = local.env
  vpc_cidr                 = var.vpc_cidr
  public_subnet_cidrs      = var.public_subnet_cidrs
  private_app_subnet_cidrs = var.private_app_subnet_cidrs
  db_subnet_cidrs          = var.db_subnet_cidrs
  az_suffix                = local.az_suffix
}

module "security" {
  source = "./modules/security"

  name_prefix = local.name_prefix
  vpc_id      = module.network.vpc_id
}

module "iam" {
  source = "./modules/iam"

  name_prefix = local.name_prefix
  env         = local.env
}

module "access" {
  source = "./modules/access"

  key_name    = var.key_name
  name_prefix = local.name_prefix
  env         = local.env
}

module "bastion_monitoring" {
  source = "./modules/bastion_monitoring"

  name_prefix               = local.name_prefix
  env                       = local.env
  region                    = var.region
  ami_id                    = data.aws_ami.ubuntu.id
  public_subnet_ids         = module.network.public_subnet_ids
  bastion_security_group_id = module.security.bastion_sg_id
  key_name                  = module.access.key_name
  iam_instance_profile_name = module.iam.instance_profile_name
}

module "swarm_master" {
  source = "./modules/swarm_master"

  name_prefix                   = local.name_prefix
  env                           = local.env
  region                        = var.region
  ami_id                        = data.aws_ami.ubuntu.id
  key_name                      = module.access.key_name
  iam_instance_profile_name     = module.iam.instance_profile_name
  master_node_security_group_id = module.security.master_node_sg_id
  private_app_subnet_ids        = module.network.private_app_subnet_ids
}

module "alb" {
  source = "./modules/alb"

  name_prefix           = local.name_prefix
  env                   = local.env
  alb_name              = var.alb_name
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  alb_security_group_id = module.security.alb_sg_id
  master_node_id        = module.swarm_master.master_node_id
}

module "postgres_ha" {
  source = "./modules/postgres_ha"

  name_prefix                  = local.name_prefix
  env                          = local.env
  ami_id                       = data.aws_ami.ubuntu.id
  db_subnet_ids                = module.network.db_subnet_ids
  db_security_group_id         = module.security.db_sg_id
  key_name                     = module.access.key_name
  iam_instance_profile_name    = module.iam.instance_profile_name
  db_name                      = var.db_name
  db_user                      = var.db_user
  db_password                  = var.db_password
  postgres_ha_instance_type    = var.postgres_ha_instance_type
  postgres_ha_root_volume_size = var.postgres_ha_root_volume_size
}

module "app" {
  source = "./modules/app"

  name_prefix                      = local.name_prefix
  env                              = local.env
  region                           = var.region
  ami_id                           = data.aws_ami.ubuntu.id
  key_name                         = module.access.key_name
  iam_instance_profile_name        = module.iam.instance_profile_name
  app_security_group_id            = module.security.app_sg_id
  private_app_subnet_ids           = module.network.private_app_subnet_ids
  backend_target_group_arn         = module.alb.backend_target_group_arn
  bastion_private_ip               = module.bastion_monitoring.bastion_private_ip
  backend_image_s3_uri             = var.backend_image_s3_uri
  desired_capacity                 = var.desired_capacity
  min_size                         = var.min_size
  max_size                         = var.max_size
  queue_metric_namespace           = var.queue_metric_namespace
  queue_metric_concert_id          = var.queue_metric_concert_id
  queue_length_per_instance_target = var.queue_length_per_instance_target
  enable_queue_consumer            = var.enable_queue_consumer
  queue_consumer_batch_size        = var.queue_consumer_batch_size
  queue_consumer_interval_seconds  = var.queue_consumer_interval_seconds
  alb_dns_name                     = module.alb.alb_dns_name

  depends_on = [module.iam]
}

module "notification" {
  source = "./modules/notification"

  name_prefix         = local.name_prefix
  telegram_bot_token  = var.telegram_bot_token
  telegram_chat_id    = var.telegram_chat_id
  discord_webhook_url = var.discord_webhook_url
}
