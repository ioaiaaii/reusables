# Define your default OPERATOR_PATH if not set
OPERATOR_PATH ?= "."

# Repo Structure and its friends
MODULE := $(shell basename `pwd`)
COMMIT := $(shell git log --pretty=format:'%h' -n 1)
TAG := $(shell git for-each-ref --count=1 --format='%(refname:short)' 'refs/tags/v[0-9]*.[0-9]*.[0-9]*' --points-at master --merged)

# Dynamically determine the branch name:
# - Use GITHUB_HEAD_REF if it is set (indicating a PR).
# - Use GITHUB_REF if it is set (indicating a regular branch push).
# - Default to the local git branch if running outside of CI/CD.
ifneq ($(GITHUB_HEAD_REF),)
  BRANCH := $(GITHUB_HEAD_REF)
else
  BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
endif

# when tag 
ifeq ($(GITHUB_REF_TYPE), tag)
  TAG := $(GITHUB_REF_NAME)
endif

SRC ?= "."
CMD_PATH := cmd/${MODULE}/*.go
BUILD_PATH := build
DEPLOY_PATH := deploy

# Get latest merged tag in master, to allow release. Else, get the branch name as version and skip tags in there
VERSION ?= ""

ifeq ($(VERSION),"")
	ifeq ($(BRANCH), HEAD)    # If in detached HEAD, fallback to commit SHA
        VERSION = $(TAG)           # Use the tag as the version
    else                           # Otherwise, use the branch name
        VERSION = $(BRANCH)
    endif
endif


KUBECONFIG ?= ""

# Build
TIMESTAMP := $(shell date '+%Y-%m-%d_%I:%M')


# Bins
CHART_TESTING_SHA := sha256:ef453de0be68d5ded26f3b3ea0c5431b396c8c48f89e2a07be7b19c4c9a68b31
HELM_SHA := sha256:6b85088a38ef34bbbdf3b91ab4e18038f35220f0f1bb1a97f94b7fde50ce66ee
UBUNTU_SHA := sha256:f0a63f53b736b9211a5313a7219f6cc012b7cf4194c7ce2248fac8162b56dceb


CT_CONTAINER_CMD := docker run -it --network host\
		-u $(shell id -u):$(shell id -g)\
		-v $(PWD)/${BUILD_PATH}/:/opt/${BUILD_PATH}\
		-v $(PWD)/${DEPLOY_PATH}/:/opt/${DEPLOY_PATH}\
		-v $(PWD)/.git/:/opt/.git:ro\
		-w "/opt"\
		quay.io/helmpack/chart-testing@${CHART_TESTING_SHA}

UBUNTU_CMD := docker run -i --rm\
		-u $(shell id -u):$(shell id -g)\
		-v $(PWD)/:/opt/:rw\
		-w "/opt"\
		ubuntu@${UBUNTU_SHA}

ifeq ($(KUBECONFIG),"")
	HELM_CONTAINER_CMD:=docker run --rm\
			-u $(shell id -u):$(shell id -g)\
			-v $(PWD)/${DEPLOY_PATH}/:/opt/${DEPLOY_PATH}:ro\
			-v ~/.kube:/root/.kube:ro\
			-w "/opt/${DEPLOY_PATH}"\
			alpine/helm@${HELM_SHA}
else
	HELM_CONTAINER_CMD:=docker run --rm\
			-u $(shell id -u):$(shell id -g)\
			-v $(PWD)/${DEPLOY_PATH}/:/opt/${DEPLOY_PATH}:ro\
			-v $(PWD)/${KUBECONFIG}:/root/.kube:ro\
			-w "/opt/${DEPLOY_PATH}"\
			alpine/helm@${HELM_SHA}
endif

# sourced :https://gist.github.com/prwhite/8168133?permalink_comment_id=2749866#gistcomment-2749866
HELP_CMD:=awk '{\
					if ($$0 ~ /^.PHONY: [a-zA-Z\-\_0-9]+$$/) {\
						command = substr($$0, index($$0, ":") + 2);\
						if (info) {\
							printf "\t\033[36m%-20s\033[0m %s\n",\
								command, info;\
							info = "";\
						}\
					} else if ($$0 ~ /^[a-zA-Z\-\_0-9.]+:/) {\
						command = substr($$0, 0, index($$0, ":"));\
						if (info) {\
							printf "\t\033[36m%-20s\033[0m %s\n",\
								command, info;\
							info = "";\
						}\
					} else if ($$0 ~ /^\#\#/) {\
						if (info) {\
							info = info"\n\t\t\t     "substr($$0, 3);\
						} else {\
							info = substr($$0, 3);\
						}\
					} else {\
						if (info) {\
							print "\n"info;\
						}\
						info = "";\
					}\
				}'				


## autogenerated help target
## add info to your command inserting before definition:
##   "## <text>"
.PHONY: help
help:
	@for file in $(MAKEFILE_LIST); do \
		cat $$file; \
	done | $(UBUNTU_CMD) $(HELP_CMD)

## Prints the current tag,branch and version
.PHONY: environment
environment:
	@echo "Tag: "${TAG}
	@echo "Branch: "${BRANCH} 
	@echo "Version: "${VERSION}
	@echo "Go path: "${GOPATH}
	@echo "Go bin: "${GOBIN}
	@echo "Go Version: "${GO_VERSION}

## Syncs gitignore configuration
.PHONY: gitignore
gitignore:
	@$(UBUNTU_CMD) bash -c "OPERATOR_PATH=$(OPERATOR_PATH) $(OPERATOR_PATH)/scripts/gitignore_sync.sh"

## Syncs pre-commit-hooks configuration
.PHONY: pre-commit-hooks-list
pre-commit-hooks-list:
	@$(UBUNTU_CMD) bash -c "OPERATOR_PATH=$(OPERATOR_PATH) ls $(OPERATOR_PATH)/pre-commit-hooks/"

## Syncs pre-commit-hooks configuration
.PHONY: pre-commit-hooks
pre-commit-hooks:
	@$(UBUNTU_CMD) bash -c "OPERATOR_PATH=$(OPERATOR_PATH) $(OPERATOR_PATH)/scripts/precommit_sync.sh"
