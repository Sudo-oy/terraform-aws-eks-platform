# Contributing to terraform-aws-eks-platform

Thanks for your interest in improving this module! Every contribution is welcome: bug reports, documentation fixes, new examples or new features.

## Ground rules

- Be kind and follow the [Code of Conduct](CODE_OF_CONDUCT.md).
- For anything bigger than a small fix, open an issue first so we can agree on the design.
- Never commit credentials, state files, `*.tfvars` with real values or account IDs.
- Report security problems privately (see [SECURITY.md](SECURITY.md)).

## Development setup

Tools:

| Tool | Version |
|---|---|
| [Terraform](https://developer.hashicorp.com/terraform/install) | >= 1.9 (CI uses 1.14) |
| [TFLint](https://github.com/terraform-linters/tflint) | >= 0.60 |
| [terraform-docs](https://terraform-docs.io/) | >= 0.20 |
| [Checkov](https://www.checkov.io/) | latest |

No AWS account is needed to develop and test: the test suite uses a mocked AWS provider.

```bash
terraform fmt -recursive
terraform init -backend=false && terraform validate
terraform test
tflint --init && tflint --recursive --config "$(pwd)/.tflint.hcl"
checkov -d . --config-file .checkov.yaml
terraform-docs .
```

## Making a change

1. Fork the repository and create a branch: `git checkout -b feat/short-description`.
2. Make your change, following the conventions below.
3. Add or update tests in `tests/` and the examples when behaviour changes.
4. Regenerate the docs with `terraform-docs .`.
5. Commit using [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `ci:`, `chore:`. Use `feat!:` or a `BREAKING CHANGE:` footer for breaking changes.
6. Open a pull request and fill in the template. CI must be green.

## Conventions

- Every variable has a `description` and a `type`. Add a `validation` block when invalid values are possible.
- Every output has a `description`.
- Prefer secure defaults. Anything that weakens security must be opt-in and documented.
- Pin external modules to an exact version.
- Keep resources behind `count`/`for_each` feature flags so the module stays composable.
- Do not add a `provider` block to the module itself (only in `examples/`).

## Releases

Releases follow [Semantic Versioning](https://semver.org/). Tags look like `v1.2.3`.
