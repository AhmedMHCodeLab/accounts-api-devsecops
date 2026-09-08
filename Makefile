.PHONY: test validate security

test:
	python policy/tests/test_iam_policy.py
	kyverno test policy/tests

validate:
	terraform -chdir=terraform fmt -check
	terraform -chdir=terraform validate
	git diff --check

security:
	$(MAKE) test
	$(MAKE) validate
	checkov --file policy/tests/terraform/good.tf \
		--external-checks-dir policy/checkov \
		--framework terraform