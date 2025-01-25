## Demo

Demo shows how to use AWS EventBride for scaling GitHub self-hosted runners on AWS and capture events in a Data Lake.

### Run the demo

1. Install [Terraform](https://www.terraform.io/).
2. `cd download` and run `terraform init && terraform apply`. to download lambdas.
3. `cd ..` back to the terraform directory.
4. Create a GitHub app, follow documentation [here]().
5. Configure the following vars: 
   ```bash
   APP_ID=YOUR_APP_ID
   APP_PRIVATE_KEY_FILE=/path-to-github-app-private-key.pem
   APP_PRIVATE_KEY=$(base64 -i $APP_PRIVATE_KEY_FILE)
   export TF_VAR_github_app='{"id": '$APP_ID', "key_base64": "'$APP_PRIVATE_KEY'"}'
   export TF_VAR_prefix=demo
   export TF_VAR_aws_region=YOUR_AWS_REGION
   ```
6. Run `terraform init && terraform apply`.
7. Next setup a GitHub actions workflow to trigger jobs.
   