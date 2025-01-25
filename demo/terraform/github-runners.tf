resource "random_id" "random" {
  byte_length = 20
}

module "runners" {
  source  = "github-aws-runners/github-runner/aws"
  version = "6.1.2"

  create_service_linked_role_spot = true
  aws_region                      = var.aws_region
  vpc_id                          = module.vpc.vpc_id
  subnet_ids                      = module.vpc.private_subnets

  prefix = var.prefix
  tags = {
    Project = "ProjectX"
  }

  github_app = {
    key_base64     = var.github_app.key_base64
    id             = var.github_app.id
    webhook_secret = random_id.random.hex
  }

  webhook_lambda_zip                = "download/webhook.zip"
  runner_binaries_syncer_lambda_zip = "download/runner-binaries-syncer.zip"
  runners_lambda_zip                = "download/runners.zip"

  enable_organization_runners = true
  runner_extra_labels         = ["default", "example"]

  # enable access to the runners via SSM
  enable_ssm_on_runners = true

  instance_types = ["m7a.large", "m5.large"]

  # override delay of events in seconds
  delay_webhook_event   = 5
  runners_maximum_count = 10

  # override scaling down
  scale_down_schedule_expression = "cron(* * * * ? *)"

  # prefix GitHub runners with the environment name
  runner_name_prefix = "${var.prefix}_"

  # enable job_retry feature. Be careful with this feature, it can lead to you hitting API rate limits.
  job_retry = {
    enable           = true
    max_attempts     = 1
    delay_in_seconds = 180
  }

}

module "webhook_github_app" {
  source  = "github-aws-runners/github-runner/aws//modules/webhook-github-app"
  version = "6.1.2"

  depends_on = [module.runners]

  github_app = {
    key_base64     = var.github_app.key_base64
    id             = var.github_app.id
    webhook_secret = random_id.random.hex
  }
  webhook_endpoint = module.runners.webhook.endpoint
}
