# AWS Serverless Web App (Terraform)

Terraform implementation of the serverless deployment described in
https://talent500.com/blog/deploy-web-app-in-aws-guide/

A static page on S3 calls an API Gateway endpoint, which invokes a Lambda function that reads an account balance from DynamoDB.

```
Browser -> S3 website -> API Gateway (POST /get_balance) -> Lambda -> DynamoDB
```

## Source

Based on the guide [How to Deploy a Web App in AWS](https://talent500.com/blog/deploy-web-app-in-aws-guide/) (Talent500). The guide does the setup by hand in the AWS console. This project does the same steps with Terraform.

| Guide step | What the guide says | Terraform |
|------------|--------------------|-----------|
| 1. S3 static hosting | Create a bucket, turn off "Block all public access", add a public `s3:GetObject` bucket policy, set CORS for GET/POST, enable static website hosting with `index.html`, upload the frontend | `aws_s3_bucket`, `aws_s3_bucket_public_access_block`, `aws_s3_bucket_policy`, `aws_s3_bucket_cors_configuration`, `aws_s3_bucket_website_configuration`, `aws_s3_object` |
| 2. DynamoDB | Create an `accounts` table with `account_id` as the key, On-Demand capacity, add sample items (`balance`, `user_name`, `user_address`) | `aws_dynamodb_table`, `aws_dynamodb_table_item` |
| 3. Lambda | Python function that reads `accountId` and calls `get_item`; returns 200 with the balance or 404; IAM policy for DynamoDB access | `aws_lambda_function`, `aws_iam_role`, `aws_iam_role_policy` |
| 4. API Gateway | REST API with a `/get_balance` POST method integrated with the Lambda, CORS enabled (OPTIONS), deploy to a `dev` stage | `aws_api_gateway_*`, `aws_lambda_permission` |
| 5. Connect the frontend | Put the API endpoint in the JavaScript; on button click POST the account ID as JSON and show the balance or error | `frontend/index.html.tpl` (URL injected at apply time) |

The guide's troubleshooting advice (enable CORS on both S3 and API Gateway, check IAM permissions, test with Postman or cURL first) is under [Troubleshooting](#troubleshooting).

## Resources

| File | Contents |
|------|----------|
| `versions.tf` | Terraform and provider versions, AWS provider config |
| `variables.tf` | `region`, `project_name`, `stage_name`, `cors_allowed_origin` |
| `main.tf` | S3 site, DynamoDB table and sample items, Lambda and IAM, API Gateway |
| `outputs.tf` | `website_url`, `api_url` |
| `lambda/get_balance.py` | Lambda handler (Python 3.12) |
| `frontend/index.html.tpl` | Frontend template; the API URL is injected at apply time |

## Prerequisites

- Terraform >= 1.3
- AWS credentials with permission to create S3, DynamoDB, Lambda, IAM and API Gateway resources

## Credentials and environment

Copy the template and fill in your values:

```bash
cp .env.example .env
```

`.env` holds `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (plus `AWS_SESSION_TOKEN` for temporary credentials) and optional `TF_VAR_*` overrides. Terraform does not read `.env` itself, so load it into your shell first:

```bash
set -a; source .env; set +a
```

`.env` is git-ignored; only `.env.example` is committed. Alternatively, skip `.env` and use `aws configure` or an AWS profile.

## Deploy

```bash
terraform init
terraform plan
terraform apply
```

Outputs:

- `website_url`: open in a browser
- `api_url`: the `/get_balance` endpoint

## Test

```bash
curl -X POST "$(terraform output -raw api_url)" \
  -H "Content-Type: application/json" \
  -d '{"accountId": "1001"}'
# {"accountId": "1001", "balance": 2500.0}
```

Unknown accounts return 404; a missing `accountId` returns 400.

Sample accounts: `1001`, `1002`, `1003`.

## Configuration

Override defaults with `-var`, `TF_VAR_*` variables in `.env`, or a `terraform.tfvars` file:

```hcl
region              = "us-east-1"
project_name        = "bank-balance-app"
stage_name          = "dev"
cors_allowed_origin = "*"
```

## Security notes

This follows the article and is intended for development only:

- The S3 bucket is public (public access block disabled, `s3:GetObject` for `*`).
- S3 CORS and API CORS allow any origin by default. Set `cors_allowed_origin` to your site's origin for anything beyond a demo (the S3 CORS rule in `main.tf` is hardcoded to `*`).
- The API has no authentication.
- The website is served over HTTP (S3 website endpoints do not support HTTPS).

## Troubleshooting

- **CORS errors:** check CORS on both the S3 bucket and the API Gateway method; make sure `cors_allowed_origin` matches the page origin.
- **Access Denied:** check the Lambda IAM role (`dynamodb:GetItem`) and the S3 bucket policy.
- Test the endpoint with `curl` or Postman before debugging the frontend.

## Clean up

```bash
terraform destroy
```
