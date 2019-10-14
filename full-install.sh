#!/usr/bin/env bash
###########
# 安裝 Lab(k8s) 課程環境
###

# 確認使用的是 root user
checkRootUser() {
  if [ `whoami | grep ^root$ | wc -l` -eq 0 ];then
    echo "[ERROR] 請使用 root 執行"
    echo "        請先執行以下指令，切換為 root 後再重試 "
    echo "------------------------------------------"
    echo "sudo su"
    echo "------------------------------------------"
    exit
  fi
}

# 確認 gcloud 指令已經 login
checkGcloudLogin() {
  if [ `gcloud config get-value core/account | grep 'compute@developer.gserviceaccount.com' | wc -l` -eq 1 ]; then
    echo "[ERROR] gcloud 指令尚未登入"
    echo "        請先執行以下指令，登入 gcloud 後再重試 "
    echo "------------------------------------------"
    echo "gcloud auth login"
    echo "------------------------------------------"
    exit
  fi
}

# 設定參數
initParameter() {
  echo "參數設定確認中..."
  
  GOOGLE_PROJECT_ID=$(gcloud projects list --filter=systex-lab  | awk 'END {print $1}')
  
  # GOOGLE_PROJECT_ID
  if [ -z $GOOGLE_PROJECT_ID  ]; then
    GOOGLE_PROJECT_ID=systex-lab-$(cat /proc/sys/kernel/random/uuid | cut -b -6)
    echo "  未定義 GOOGLE_PROJECT_ID.   由系統自動產生...(GOOGLE_PROJECT_ID=$GOOGLE_PROJECT_ID)" 
  else
    echo "  系統參數 GOOGLE_PROJECT_ID  已設定...........(GOOGLE_PROJECT_ID=$GOOGLE_PROJECT_ID)" 
  fi
  
  # GOOGLE_ZONE
  if [ -z $GOOGLE_ZONE  ]; then
    GOOGLE_ZONE=asia-east1-$(ary=(a b c) && echo ${ary[$(($RANDOM%3))]})
    echo "  未定義 GOOGLE_ZONE.         使用預設值.......(GOOGLE_ZONE=$GOOGLE_ZONE)"
  else
    echo "  系統參數 GOOGLE_ZONE        已設定...........(GOOGLE_ZONE=$GOOGLE_ZONE)" 
  fi
  
  # GOOGLE_GKE_NAME
  if [ -z $GOOGLE_GKE_NAME  ]; then
    GOOGLE_GKE_NAME=devops-camp
    echo "  未定義 GOOGLE_GKE_NAME.     使用預設值.......(GOOGLE_GKE_NAME=$GOOGLE_GKE_NAME)"
  else
    echo "  系統參數 GOOGLE_GKE_NAME    已設定...........(GOOGLE_GKE_NAME=$GOOGLE_GKE_NAME)" 
  fi

  # GOOGLE_GKE_MACHINE
  if [ -z $GOOGLE_GKE_MACHINE  ]; then
    GOOGLE_GKE_MACHINE=n1-standard-2
    echo "  未定義 GOOGLE_GKE_MACHINE.  使用預設值.......(GOOGLE_GKE_MACHINE=$GOOGLE_GKE_MACHINE)"
  fi

  # GOOGLE_GKE_NODES
  if [ -z $GOOGLE_GKE_NODES  ]; then
    GOOGLE_GKE_NODES=3
    echo "  未定義 GOOGLE_GKE_NODES.    使用預設值.......(GOOGLE_GKE_NODES=$GOOGLE_GKE_NODES)"
  fi

  # GOOGLE_GCE_IMAGE
  #if [ -z $GOOGLE_GKE_VERSION  ]; then
  #  GOOGLE_GKE_VERSION=1.12.8-gke.6
  #  echo "  未定義 GOOGLE_GKE_VERSION.  使用預設值.......(GOOGLE_GKE_VERSION=$GOOGLE_GKE_VERSION)"
  #fi

  # HELM_VERSION
  if [ -z $HELM_VERSION  ]; then
    HELM_VERSION=v2.13.1
    echo "  未定義 HELM_VERSION.        使用預設值.......(HELM_VERSION=$HELM_VERSION)"
  fi

  # ISTIO_VERSION
  if [ -z $ISTIO_VERSION  ]; then
    ISTIO_VERSION=1.0.8
    echo "  未定義 ISTIO_VERSION.       使用預設值.......(ISTIO_VERSION=$ISTIO_VERSION)"
  fi

  read -p "確認開始安裝(Y/n)?" yn
  case $yn in
      [Nn]* ) echo "動作取消 "; exit;;
  esac  
}

# 安裝 kubectl 指令
installKubectl() {
  echo "正在安裝 kubectl 指令..."
  printf "  安裝 kubectl 套件中......"
  yum -y install kubectl > /dev/null 2>&1 && echo "完成"
}

createProject() {
  echo "正在建立GCP 專案..."
  gcloud projects create $GOOGLE_PROJECT_ID > /dev/null 2>&1
  echo "export \$(cat .my-env|xargs)" | tee -a ~/.profile > /dev/null 2>&1

  printf "  切換專案至($GOOGLE_PROJECT_ID)..."
  gcloud config set project $GOOGLE_PROJECT_ID > /dev/null 2>&1 && echo "完成"
    
    
  BILLING_ACCOUNT=$(gcloud beta billing accounts list | grep True | awk -F" " '{print $1}')
  gcloud beta billing projects link $GOOGLE_PROJECT_ID --billing-account $BILLING_ACCOUNT > /dev/null 2>&1
}

createK8S() {
  echo "正在建立GKE..."
  
  printf "  啟用 Container API..."
  gcloud services enable container.googleapis.com --project=$GOOGLE_PROJECT_ID  > /dev/null 2>&1 && echo "完成"

  printf "  開始建立 GKE($GOOGLE_GKE_NAME)..."
  if [ $(gcloud container clusters list --project=$GOOGLE_PROJECT_ID | grep $GOOGLE_GKE_NAME | wc -l) -eq 0 ]; then
    gcloud container clusters create $GOOGLE_GKE_NAME \
        --project=$GOOGLE_PROJECT_ID \
        --machine-type=$GOOGLE_GKE_MACHINE \
        --zone=$GOOGLE_ZONE \
        --num-nodes=$GOOGLE_GKE_NODES \
        --disk-type "pd-standard" \
        --disk-size "500" \
        > /dev/null 2>&1 && echo "完成"
  else
    echo "已存在"
  fi
  
  printf "  正在設定授權..."
  kubectl create clusterrolebinding cluster-admin-binding \
    --clusterrole=cluster-admin \
    --user=$(gcloud config get-value core/account)\
    > /dev/null 2>&1 && echo "完成"

}

installHelm() {

  cd $CURRENT_HOME

  echo "安裝 Helm ..."
  printf "  正在下載 Helm($HELM_VERSION)..."
  curl -s https://raw.githubusercontent.com/helm/helm/master/scripts/get | DESIRED_VERSION=$HELM_VERSION bash > /dev/null 2>&1
  helm init > /dev/null 2>&1 && echo "完成"

  printf "  正在授權 Tiller..."
  kubectl create serviceaccount --namespace kube-system tiller > /dev/null 2>&1
  kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller > /dev/null 2>&1
  kubectl patch deploy --namespace kube-system tiller-deploy -p '{"spec":{"template":{"spec":{"serviceAccount":"tiller"}}}}' \
  > /dev/null 2>&1 && echo "完成"

  printf "  等待 Tiller 服務啟動中 ..."
  while [ `kubectl get po -n kube-system | grep tiller-deploy | grep '1/1' | wc -l` -eq 0 ]
  do
    sleep 1
  done
  echo "已啟動."
}

installJenkins() {
  cd $CURRENT_HOME

  echo "安裝 Jenkins ..."

  printf "  正在授權 jenkins-deployer..."

  # Google Container Registry 
  gcloud iam service-accounts create jenkins-deployer > /dev/null 2>&1
  #gsutil iam ch serviceAccount:jenkins-deployer@${GOOGLE_PROJECT_ID}.iam.gserviceaccount.com:admin gs://artifacts.${GOOGLE_PROJECT_ID}.appspot.com/  > /dev/null 2>&1
  gcloud projects add-iam-policy-binding ${GOOGLE_PROJECT_ID} \
      --member="serviceAccount:jenkins-deployer@${GOOGLE_PROJECT_ID}.iam.gserviceaccount.com" \
      --role='roles/storage.admin' > /dev/null 2>&1
  gcloud iam service-accounts keys create key.json --iam-account=jenkins-deployer@${GOOGLE_PROJECT_ID}.iam.gserviceaccount.com > /dev/null 2>&1
  docker login -u _json_key -p "$(cat key.json)" https://gcr.io  > /dev/null 2>&1
  kubectl create configmap google-container-key --from-file=.docker/config.json  > /dev/null 2>&1

  kubectl create sa jenkins-deployer > /dev/null 2>&1
  kubectl create clusterrolebinding jenkins-deployer-role --clusterrole=cluster-admin --serviceaccount=default:jenkins-deployer > /dev/null 2>&1
  K8S_ADMIN_CREDENTIAL=$(kubectl describe secret jenkins-deployer | grep token: | awk -F" " '{print $2}')
  cat <<EOF | kubectl apply -f -  > /dev/null 2>&1 && echo "完成"
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: fabric8-rbac
subjects:
  - kind: ServiceAccount
    name: default
    namespace: default
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF

  printf "  正在安裝 jenkins-slave ... "
  printf "build..." && docker build -t gcr.io/${GOOGLE_PROJECT_ID}/jnlp-slave:v1 devops-hands-on/jenkins/slave > /dev/null 2>&1
  printf "push..." && docker push gcr.io/${GOOGLE_PROJECT_ID}/jnlp-slave:v1 > /dev/null 2>&1
  echo "完成"

  printf "  正在安裝 jenkins:lts ..."
  helm install --name jenkins \
    --set Master.ServiceType=ClusterIP \
    --set Master.K8sAdminCredential=$K8S_ADMIN_CREDENTIAL \
    --set Agent.Image=gcr.io/${GOOGLE_PROJECT_ID}/jnlp-slave \
    --set Agent.ImageTag=v1 \
    --set Master.AdminPassword=systex \
    --set Master.GoogleProjectId=${GOOGLE_PROJECT_ID} \
    devops-hands-on/jenkins > /dev/null 2>&1 && echo "完成"
}

installIstio() {
  cd $CURRENT_HOME

  echo "安裝 Istio ..."

  printf "  正在下載 Istio:$ISTIO_VERSION ..."
  curl -s -L https://git.io/getLatestIstio | ISTIO_VERSION=$ISTIO_VERSION sh - > /dev/null 2>&1 && echo "完成"
  cd istio-$ISTIO_VERSION
  
  printf "  開始安裝 Istio ..."
  kubectl create namespace istio-system > /dev/null 2>&1 
  cat <<EOF | kubectl apply -f - > /dev/null 2>&1 
apiVersion: v1
kind: Secret
metadata:
  name: kiali
  namespace: istio-system
  labels:
    app: kiali
type: Opaque
data:
  username: YWRtaW4=
  passphrase: c3lzdGV4
EOF
 # helm template --name istio-init --namespace istio-system install/kubernetes/helm/istio-init/ | kubectl apply -f -
  helm template install/kubernetes/helm/istio \
    --name istio --namespace istio-system \
    --set sidecarInjectorWebhook.enabled=true \
    --set pilot.traceSampling=100.0 \
    --set pilot.resources.requests.cpu=100m \
    --set pilot.resources.requests.memory=256Mi \
    --set grafana.enabled=true \
    --set tracing.enabled=true \
    --set servicegraph.enabled=true \
    --set kiali.enabled=true \
    --set kiali.createDemoSecret=true \
  |  kubectl apply -f - > /dev/null 2>&1
  printf "等待服務啟動中..."
  while [ `kubectl get po -n istio-system | grep istio-sidecar-injector | grep Running | grep '1/1' | wc -l` -eq 0 ]
  do
    sleep 1
  done  
  echo "完成"

  printf "  設定自動注入 sidecar ..."
  kubectl label namespace default istio-injection=enabled > /dev/null 2>&1 && echo "完成"

  printf "  安裝 Bookinfo 範例程式 ..."
  kubectl apply -f samples/bookinfo/platform/kube/bookinfo.yaml > /dev/null 2>&1
  kubectl apply -f samples/bookinfo/networking/bookinfo-gateway.yaml > /dev/null 2>&1
  kubectl apply -f samples/bookinfo/networking/destination-rule-all.yaml > /dev/null 2>&1 && echo "完成"
}

installEFK() {
  cd $CURRENT_HOME

  echo "安裝 Elasticsearch + Fluentd + Kibana ..."
  printf "  安裝中 ..."
  kubectl apply -f devops-hands-on/logging-efk.yaml > /dev/null 2>&1 && echo "完成"

}

installKSM() {
  cd $CURRENT_HOME

  echo "安裝 Kube-state-metrics ..."
  printf "  安裝中 ..."
  kubectl apply -f devops-hands-on/kube-state-metrics/app-crd.yaml > /dev/null 2>&1 
  kubectl apply -f devops-hands-on/kube-state-metrics/prometheus-metrics_sa_manifest.yaml --namespace logging > /dev/null 2>&1 
  kubectl apply -f devops-hands-on/kube-state-metrics/prometheus-metrics_manifest.yaml --namespace logging  > /dev/null 2>&1 && echo "完成"

}

confirmInstall() {
  cd $CURRENT_HOME
  
  echo "確認安裝項目清單"
  
  printf "  GCP Project($GOOGLE_PROJECT_ID) ............."
  if [ $(gcloud projects list | grep $GOOGLE_PROJECT_ID | wc -l ) -eq 1 ]; then
    echo "完成."
  else 
    echo "失敗."
  fi
  printf "  GCP Kubernetes Cluster($GOOGLE_GKE_NAME) ........"
  if [ $(gcloud container clusters list | grep $GOOGLE_GKE_NAME | wc -l ) -eq 1 ]; then
    echo "完成."
  else 
    echo "失敗."
  fi

  printf "  Istio System ..............................."
  if [ $(kubectl get po -n istio-system | grep -E "servicegraph|prometheus|kiali|tracing|telemetry|sidecar|policy|egressgateway|galley|ingressgateway|pilot" | wc -l ) -ge 11 ]; then
    echo "已安裝."
  else 
    echo "失敗."
  fi

  printf "  Elasticsearch+Kibana+Fluentd ..............."
  if [ $(kubectl get po -n logging | grep -E "elasticsearch|kibana|fluentd" | wc -l ) -eq 3 ]; then
    echo "已安裝."
  else 
    echo "失敗."
  fi

  printf "  Kube state metrics ........................."
  if [ $(kubectl get po -n logging | grep "prometheus-metrics" | wc -l ) -ge 5 ]; then
    echo "已安裝."
  else 
    echo "失敗."
  fi

  printf "  Jenkins ...................................."
  if [ $(helm list | grep jenkins | wc -l ) -eq 1 ]; then
    echo "已安裝."
  else 
    echo "失敗."
  fi  
}

setupService() {
  cd $CURRENT_HOME
  
  echo "設定對外服務項目..."
  
  printf "  等待對外IP配發中..."
  while [ `kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}' | wc -c` -eq 0 ]
  do
    sleep 1
  done  
  INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  echo "(IP=$INGRESS_HOST)...完成"

  printf "  開啟對外服務中..."
  helm template --set istio.ingressgateway.ip=$INGRESS_HOST devops-hands-on/svc | kubectl apply -f - > /dev/null 2>&1 && echo "完成"
}

CURRENT_HOME=$(pwd)

rm -rf ~/.my-env
rm -rf key.json
rm -rf devops-hands-on

git clone https://github.com/abola/devops-hands-on.git

initParameter
createProject
createK8S
installHelm
installJenkins
installIstio
installEFK
installKSM
setupService
confirmInstall

> ~/.my-env
echo "GOOGLE_PROJECT_ID=$GOOGLE_PROJECT_ID" >> ~/.my-env
echo "GOOGLE_ZONE=$GOOGLE_ZONE" >> ~/.my-env
echo "GOOGLE_GKE_NAME=$GOOGLE_GKE_NAME" >> ~/.my-env
echo "INGRESS_HOST=$INGRESS_HOST" >> ~/.my-env

cat <<EOF
-------------------------------------------------------------
環境安裝完成
----------
Istio Bookinfo 示範程式: http://bookinfo.$INGRESS_HOST.nip.io/
K8S Health Monitoring  : http://grafana.$INGRESS_HOST.nip.io/
Kiali Service Graph    : http://kiali.$INGRESS_HOST.nip.io/
Jaeger Tracing         : http://jaeger.$INGRESS_HOST.nip.io/
Kibana Logging         : http://kibana.$INGRESS_HOST.nip.io/
Jenkins CI/CD          : http://jenkins.$INGRESS_HOST.nip.io/
-------------------------------------------------------------
EOF
