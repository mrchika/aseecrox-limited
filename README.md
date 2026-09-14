# Aseecrox Limited website

A static portfolio and client inquiry form backed by AWS API Gateway, Lambda, DynamoDB, and Amazon SES.

## Deploy the inquiry API

Run these commands from this folder with AWS credentials configured for the `us-east-1` region:

```powershell
terraform init
terraform apply
terraform output -raw api_endpoint
```

Copy the output URL into `AWS_API_ENDPOINT` in `index.html`. The endpoint should end in `/prod/contact`. Commit the updated `index.html` before publishing the site on GitHub Pages or another static host.

The SES sender and recipient default to `Aseecroxlimited@gmail.com`. That address must be verified in SES in `us-east-1`. If the AWS account is still in the SES sandbox, client email addresses may also need verification; request production access when the site is ready for public leads.

## GitHub Pages

Publish the folder as the site root. The inquiry API remains in AWS; GitHub Pages only serves `index.html`, `styles.css`, and the logo.

Do not commit Terraform state, Terraform variables, or the generated Lambda ZIP. The included `.gitignore` excludes them.
