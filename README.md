# myapp — Production CI/CD Pipeline

A complete CI/CD setup: GitHub Actions (primary) + Jenkins (alternative),
Docker, AWS ECR + ECS Fargate (or EC2), Slack + email notifications,
secrets management, and a manual production approval gate.

---

## 1. Local development

```bash
npm install
npm run lint
npm test
npm start          # http://localhost:3000  and /health
```

Docker locally:
```bash
docker build -t myapp:local .
docker run -p 3000:3000 myapp:local
# or
docker compose up --build
```

---

## 2. Repository setup

```bash
git init
git add .
git commit -m "Initial commit: app + pipeline"
git branch -M main
git remote add origin https://github.com/<you>/myapp.git
git push -u origin main
```

The CI workflow (`.github/workflows/ci.yml`) runs automatically on this push —
check the **Actions** tab.

---

## 3. AWS prerequisites (one-time setup)

### IAM user for CI/CD
Create an IAM user (e.g. `github-actions-deployer`) with a policy granting
**only**:
- `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`,
  `ecr:GetDownloadUrlForLayer`, `ecr:BatchGetImage`, `ecr:PutImage`,
  `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`
- `ecs:DescribeTaskDefinition`, `ecs:RegisterTaskDefinition`,
  `ecs:UpdateService`, `ecs:DescribeServices`
- `iam:PassRole` (scoped to the ECS task execution role ARN)

Generate an access key for this user — used as `AWS_ACCESS_KEY_ID` /
`AWS_SECRET_ACCESS_KEY` secrets below.

> Production teams should replace long-lived keys with OIDC
> (`aws-actions/configure-aws-credentials` supports `role-to-assume`)
> so no static credentials are stored at all.

### ECR repository
```bash
aws ecr create-repository --repository-name myapp --region us-east-1
```

### ECS cluster, task definitions, services (Fargate path)
```bash
aws ecs create-cluster --cluster-name myapp-cluster
```
Then create:
- Task definitions `myapp-staging` and `myapp-production`
  (container name must be `myapp`, port 3000, Fargate compatible,
  with an execution role that can pull from ECR).
- ECS services `myapp-staging` and `myapp-production` on `myapp-cluster`,
  attached to an ALB target group with health check path `/health`.

### EC2 path (alternative, see `deploy-ec2.yml`)
- Launch a staging and a production EC2 instance with Docker installed.
- Attach an instance profile/IAM role allowing ECR pull, **or** rely on
  the SSH session running `aws ecr get-login-password` with credentials
  configured on the box.
- Open port 3000 (or front with Nginx/ALB).
- Add the instance's public IP/DNS as `STAGING_HOST` / `PROD_HOST` secrets.

---

## 4. GitHub configuration

### Secrets — Settings → Secrets and variables → Actions

| Secret | Used for |
|---|---|
| `AWS_ACCESS_KEY_ID` | ECR login, ECS deploy |
| `AWS_SECRET_ACCESS_KEY` | ECR login, ECS deploy |
| `SLACK_WEBHOOK_URL` | Slack notifications (Slack → Apps → Incoming Webhooks) |
| `EMAIL_USERNAME` / `EMAIL_PASSWORD` | Failure emails (use an app password, not your real password) |
| `SSH_PRIVATE_KEY` / `SSH_USER` / `STAGING_HOST` / `PROD_HOST` | EC2 path only |

### Environments — Settings → Environments

1. **staging** — no protection rules needed (auto-deploys).
2. **production** — enable **Required reviewers**, add yourself/your team.
   This is what creates the manual approval gate in `deploy-production`.
   Optionally restrict to the `main` branch only.

---

## 5. Pipeline behaviour

| Trigger | Workflow | What happens |
|---|---|---|
| Push to any branch / PR to `main` | `ci.yml` | lint, test, coverage, `npm audit` |
| Push to `main` | `deploy.yml` (ECS) or `deploy-ec2.yml` | test → build & push to ECR → deploy staging → **wait for approval** → deploy production |

Every staging/production step posts to Slack on success **and** failure.
Production failures additionally trigger an email to `devops-team@example.com`
(change this address in the workflow files).

---

## 6. Jenkins alternative

If your org runs Jenkins instead of/alongside GitHub Actions:

1. Run Jenkins (e.g. `docker run -p 8080:8080 -p 50000:50000 jenkins/jenkins:lts`).
2. Install plugins: Pipeline, Docker, Amazon ECR/AWS Credentials, Slack
   Notification, Email Extension, JUnit, HTML Publisher.
3. Add credentials:
   - `aws-jenkins-creds` (AWS access key/secret, scoped as above)
   - `ecr-registry-url` (secret text: `<account-id>.dkr.ecr.us-east-1.amazonaws.com`)
4. New Item → Pipeline → "Pipeline script from SCM" → point at this repo's
   `Jenkinsfile`.
5. The "Approve Production?" stage pauses and waits for a member of
   `devops-team` to click **Deploy Now**.

`jq` must be installed on the Jenkins agent for `scripts/update-task-def.sh`.

---

## 7. Deployment strategy notes

- Images are tagged with the **Git SHA** (immutable, traceable) and also
  `latest` for convenience — never deploy using `latest` as the source of
  truth, only the SHA tag.
- ECS `wait-for-service-stability: true` / `aws ecs wait services-stable`
  gives you a **rolling deployment** with automatic health-check-based
  rollout — if new tasks fail health checks, ECS won't drain the old ones.
- For zero-downtime blue-green or canary, layer in CodeDeploy (ECS
  blue-green) or ALB weighted target groups — see PDF Module 7 for the
  Terraform snippet.

---

## 8. Troubleshooting

See the "Common Errors & Fixes" table in the CI/CD Mastery Guide (Module 10).
Most issues are: wrong IAM permissions, ECS service stuck in `PENDING`
(check ALB health check path/port), or secrets not redacting because they
were referenced incorrectly (always `${{ secrets.NAME }}`, never hardcoded).
