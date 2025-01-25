module "github-runner_download-lambda" {
  source  = "github-aws-runners/github-runner/aws//modules/download-lambda"
  version = "6.1.2"
  # insert the 1 required variable here

  lambdas = [
    {
      name = "webhook"
      tag  = "v6.1.2"
    },
    {
      name = "runners"
      tag  = "v6.1.2"
    },
    {
      name = "runner-binaries-syncer"
      tag  = "v6.1.2"
    }
  ]

}