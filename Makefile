# Current Operator version
VERSION ?= 0.0.0
# Default bundle image tag
BUNDLE_IMG ?= controller-bundle:$(VERSION)
# Options for 'bundle-build'
ifneq ($(origin CHANNELS), undefined)
BUNDLE_CHANNELS := --channels=$(CHANNELS)
endif
ifneq ($(origin DEFAULT_CHANNEL), undefined)
BUNDLE_DEFAULT_CHANNEL := --default-channel=$(DEFAULT_CHANNEL)
endif
BUNDLE_METADATA_OPTS ?= $(BUNDLE_CHANNELS) $(BUNDLE_DEFAULT_CHANNEL)

# Image URL to use all building/pushing image targets
IMG ?= tyk-operator:latest
# Produce CRDs that work back to Kubernetes 1.11 (no version conversion)
CRD_OPTIONS ?= "crd:trivialVersions=true"
#The name of the kind cluster used for development
CLUSTER_NAME ?= kind

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

all: manager

# Run tests
#test: generate fmt vet manifests
#	go test ./... -coverprofile cover.out
# Run tests
ENVTEST_ASSETS_DIR=$(shell pwd)/testbin
# skip bdd when doing unit testing
UNIT_TEST=$(shell go list ./... | grep -v bdd)
test: generate fmt vet manifests
	mkdir -p ${ENVTEST_ASSETS_DIR}
	test -f ${ENVTEST_ASSETS_DIR}/setup-envtest.sh || curl -sSLo ${ENVTEST_ASSETS_DIR}/setup-envtest.sh https://raw.githubusercontent.com/kubernetes-sigs/controller-runtime/master/hack/setup-envtest.sh
	source ${ENVTEST_ASSETS_DIR}/setup-envtest.sh; fetch_envtest_tools $(ENVTEST_ASSETS_DIR); setup_envtest_env $(ENVTEST_ASSETS_DIR); go test ${UNIT_TEST}  -coverprofile cover.out

# Build manager binary
manager: generate fmt vet
	go build -o bin/manager main.go

# Run against the configured Kubernetes cluster in ~/.kube/config
run: generate fmt vet manifests
	TYK_URL=${TYK_URL} TYK_MODE=${TYK_MODE} TYK_TLS_INSECURE_SKIP_VERIFY=${TYK_TLS_INSECURE_SKIP_VERIFY} TYK_ADMIN_AUTH=${TYK_ADMIN_AUTH} TYK_AUTH=${TYK_AUTH} TYK_ORG=${TYK_ORG} ENABLE_WEBHOOKS=${ENABLE_WEBHOOKS} go run ./main.go

# Install CRDs into a cluster
install: manifests kustomize
	$(KUSTOMIZE) build config/crd | kubectl apply -f -

# Uninstall CRDs from a cluster
uninstall: manifests kustomize
	$(KUSTOMIZE) build config/crd | kubectl delete -f -

# Deploy controller in the configured Kubernetes cluster in ~/.kube/config
deploy: manifests kustomize
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	$(KUSTOMIZE) build config/default | kubectl apply -f -

helm: kustomize
	$(KUSTOMIZE) build config/crd > ./helm/crds/crds.yaml
	$(KUSTOMIZE) build config/helm |go run hack/helm/pre_helm.go > ./helm/templates/all.yaml

manifests: controller-gen
	$(CONTROLLER_GEN) $(CRD_OPTIONS) rbac:roleName=manager-role webhook paths="./..." output:crd:artifacts:config=config/crd/bases

# Run go fmt against code
fmt:
	go fmt ./...

# Run go vet against code
vet:
	go vet ./...

# Generate code
generate: controller-gen
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."

# Build the docker image
docker-build: test
	docker build . -t ${IMG}

# Build the docker image
docker-build-notest:
	docker build . -t ${IMG}

# Push the docker image
docker-push:
	docker push ${IMG}

# Make release
release:
	git checkout master
	sed -i -e "s|\(version\):.*|\1: ${VERSION} # version of the chart|" helm/Chart.yaml
	git add helm/Chart.yaml
	git commit -m "version to: v${VERSION}"
	git push origin master && git tag v${VERSION} && git push --tags

# find or download controller-gen
# download controller-gen if necessary
controller-gen:
ifeq (, $(shell which controller-gen))
	@{ \
	set -e ;\
	CONTROLLER_GEN_TMP_DIR=$$(mktemp -d) ;\
	cd $$CONTROLLER_GEN_TMP_DIR ;\
	go mod init tmp ;\
	go get sigs.k8s.io/controller-tools/cmd/controller-gen@v0.3.0 ;\
	rm -rf $$CONTROLLER_GEN_TMP_DIR ;\
	}
CONTROLLER_GEN=$(GOBIN)/controller-gen
else
CONTROLLER_GEN=$(shell which controller-gen)
endif

kustomize:
ifeq (, $(shell which kustomize))
	@{ \
	set -e ;\
	KUSTOMIZE_GEN_TMP_DIR=$$(mktemp -d) ;\
	cd $$KUSTOMIZE_GEN_TMP_DIR ;\
	go mod init tmp ;\
	go get sigs.k8s.io/kustomize/kustomize/v3@v3.8.6 ;\
	rm -rf $$KUSTOMIZE_GEN_TMP_DIR ;\
	}
KUSTOMIZE=$(GOBIN)/kustomize
else
KUSTOMIZE=$(shell which kustomize)
endif

# Generate bundle manifests and metadata, then validate generated files.
.PHONY: bundle
bundle: manifests kustomize
	operator-sdk generate kustomize manifests -q
	cd config/manager && $(KUSTOMIZE) edit set image controller=$(IMG)
	$(KUSTOMIZE) build config/manifests | operator-sdk generate bundle -q --overwrite --version $(VERSION) $(BUNDLE_METADATA_OPTS)
	operator-sdk bundle validate ./bundle

# Build the bundle image.
.PHONY: bundle-build
bundle-build:
	docker build -f bundle.Dockerfile -t $(BUNDLE_IMG) .

.PHONY: cross-build-image
cross-build-image:
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 GO111MODULE=on go build -mod=vendor -a -o manager.linux main.go
	docker build -f cross.Dockerfile . -t ${IMG}

.PHONY: cross-build-image
install-cert-manager:
	@echo "===> installing cert-manager"
	kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.0.4/cert-manager.yaml
	kubectl rollout status  deployment/cert-manager -n cert-manager
	kubectl rollout status  deployment/cert-manager-cainjector -n cert-manager
	kubectl rollout status  deployment/cert-manager-webhook -n cert-manager

.PHONY: install-operator-helm
install-operator-helm: cross-build-image manifests helm
	@echo "===> installing operator with helmr"
	go run hack/cluster/load_image.go -image ${IMG} -cluster=${CLUSTER_NAME}
	helm install ci ./helm --values ./ci/helm_values.yaml -n tyk-operator-system --wait

.PHONY: scrap
scrap: generate manifests helm cross-build-image
	@echo "===> re installing operator with helm"
	go run hack/cluster/load_image.go -image ${IMG} -cluster=${CLUSTER_NAME}
	helm uninstall ci -n tyk-operator-system
	helm install ci ./helm --values ./ci/helm_values.yaml -n tyk-operator-system --wait

.PHONY: setup-pro
setup-pro:  install-cert-manager
	@echo "===> installing tyk-pro"
	sh ./ci/deploy_tyk_pro.sh
	@echo "===> bootstrapping tyk dashboard (initial org + user)"
	sh ./ci/bootstrap_org.sh
	cat bootstrapped
	@echo "===> setting operator dash secrets"
	sh ./ci/operator_pro_secrets.sh

.PHONY: setup-ce
setup-ce: install-cert-manager
	@echo "===> installing tyk-ce"
	sh ./ci/deploy_tyk_ce.sh
	@echo "setting operator secrets"
	sh ./ci/operator_ce_secrets.sh

.PHONY: boot-pro
boot-pro: setup-pro install-operator-helm
	@echo "******** Successful boot strapped pro dev env ************"

.PHONY: boot-ce
boot-ce:setup-ce install-operator-helm
	@echo "******** Successful boot strapped ce dev env ************"

.PHONY: bdd
bdd:
	go test -timeout 400s -v  ./bdd

.PHONY: test-all
test-all: test bdd
