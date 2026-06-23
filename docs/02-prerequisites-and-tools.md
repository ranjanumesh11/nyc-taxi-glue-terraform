# Prerequisites and Tools

All tools were installed on Windows 10 using `winget`. Run these once on a new machine.

## AWS CLI v2

```powershell
winget install --id Amazon.AWSCLI --silent --accept-package-agreements --accept-source-agreements
```

Verify:
```powershell
aws --version
# aws-cli/2.35.10 Python/3.14.5 Windows/10 exe/AMD64
```

### Configure AWS SSO (do this once)

This uses IAM Identity Center — no long-lived access keys stored on disk.

The config file is at `C:\Users\<you>\.aws\config` and contains:

```ini
[sso-session admin]
sso_start_url = https://ssoins-7223feb6e88fa100.portal.us-east-1.app.aws
sso_region = us-east-1
sso_registration_scopes = sso:account:access

[profile default]
sso_session = admin
sso_account_id = 721559935914
sso_role_name = AdministratorAccess
region = us-east-1
output = json
```

### Log in (do this each session — opens browser)

```powershell
aws sso login --profile default
```

Your browser opens → log in with your IAM Identity Center credentials → CLI gets temporary credentials valid for the session.

### Verify you are authenticated

```powershell
aws sts get-caller-identity --profile default
```

Expected output:
```json
{
    "UserId": "AROA....:ranjanadmin",
    "Account": "721559935914",
    "Arn": "arn:aws:sts::721559935914:assumed-role/AWSReservedSSO_AdministratorAccess_.../ranjanadmin"
}
```

---

## GitHub CLI

```powershell
winget install --id GitHub.cli --silent --accept-package-agreements --accept-source-agreements
```

Verify:
```powershell
gh --version
# gh version 2.95.0
```

### Authenticate

```powershell
gh auth login --web --git-protocol https
# Opens browser → log in → authorize
```

You also need the `workflow` scope to push GitHub Actions files:

```powershell
gh auth refresh --hostname github.com --scopes workflow
# Opens browser → approve additional scope
```

---

## Terraform CLI

```powershell
winget install --id Hashicorp.Terraform --silent --accept-package-agreements --accept-source-agreements
```

Verify:
```powershell
terraform version
# Terraform v1.15.6
```

Terraform CLI is used locally and by the GitHub Actions runner to communicate with Terraform Cloud. The actual plan/apply executes **inside Terraform Cloud**, not on your local machine.

---

## IAM Identity Center — SSO vs IAM users explained

| | IAM User | Identity Center User |
|--|--|--|
| Login URL | `721559935914.signin.aws.amazon.com/console` | `ssoins-7223feb6e88fa100.portal.us-east-1.app.aws` |
| Credentials | Username + password (set once) | Username + password (set via email verification) |
| CLI auth | `aws configure` with access keys | `aws sso login` — no keys stored |
| Best practice | No (long-lived keys) | Yes |

These are **completely separate accounts with separate passwords.** The Identity Center password is set when AWS sends you a verification email after user creation.

---

## Refreshing expired CLI sessions

AWS SSO tokens expire. When you see this error:
```
Error loading SSO Token: Token for admin does not exist
```

Just re-run:
```powershell
aws sso login --profile default
```
