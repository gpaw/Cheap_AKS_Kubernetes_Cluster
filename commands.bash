docker run -ti --rm --name azure-cli-tutorial -v /Users/georgepaw/projects/Cheap_AKS_Kubernetes_Cluster:/home -w /home mcr.microsoft.com/azure-cli

# Install AKS CLI
az aks install-cli

# install extension to allow spot node creation
az extension add --name aks-preview

# Set Global Variables
export SUBSCRIPTION=150b6c6e-8d2f-4b6e-a9c6-3ca412277e03
export LOCATION=westus
export RESOURCE_GROUP=CheapAKSTutorial
export AKS_CLUSTER=CheapAKSCluster
export MC_RESOURCE_GROUP=MC_${RESOURCE_GROUP}_${AKS_CLUSTER}_${LOCATION}
export SPOT_VMSS=spotnodepool
export VM_SIZE=Standard_A2_v2

# Create SSH key pair to login to instance in the future
ssh-keygen -t rsa -b 4096 -C "CheapAKSCluster"
# Enter filename: ./cheapakscluster

# Login for the first time
az login

# Set your default subscription
az account set --subscription $SUBSCRIPTION

# Create a resource group in West US2
az group create --name $RESOURCE_GROUP \
	--subscription $SUBSCRIPTION \
	--location $LOCATION 

# Create a basic single-node AKS cluster - wait 3 mins
az aks create \
	--subscription $SUBSCRIPTION \
    --resource-group $RESOURCE_GROUP  \
    --name $AKS_CLUSTER \
    --vm-set-type VirtualMachineScaleSets \
    --node-count 1 \
    --ssh-key-value cheapakscluster.pub\
    --load-balancer-sku standard \
    --enable-cluster-autoscaler \
    --min-count 1 \
    --max-count 3

# Make note of where service principal is
ls -lstr $HOME/.azure/aksServicePrincipal.json

# Get AKS Credentials
az aks get-credentials \
	--subscription $SUBSCRIPTION \
	--resource-group $RESOURCE_GROUP \
    --name $AKS_CLUSTER


# Add Spot Nodepool - Only works for Pay-As-You-Go - wait 3 mins
az aks nodepool add \
	--subscription $SUBSCRIPTION \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $AKS_CLUSTER \
    --name $SPOT_VMSS \
    --priority Spot \
    --spot-max-price -1 \
    --eviction-policy Delete \
    --node-vm-size $VM_SIZE \
    --node-count 1 \
    --node-osdisk-size 32 \
    --enable-cluster-autoscaler \
    --min-count 1 \
    --max-count 3

# Confirm that the spot nodepool has started
kubectl get node

# only to allow coredns pods to run on the first node
kubectl taint nodes --all kubernetes.azure.com/scalesetpriority-

# Get VMSS name - sometimes it doesn't work, gives []
export NODE_VMSS=$(az vmss list \
    --resource-group $MC_RESOURCE_GROUP \
    --subscription $SUBSCRIPTION \
    --query '[0].name' -otsv)

# make sure it is nodepool1
echo $NODE_VMSS
# aks-nodepool1-34579063-vmss

# Reduce VMSS to 0 nodes
az vmss scale \
	--subscription $SUBSCRIPTION \
	--resource-group $MC_RESOURCE_GROUP \
	--name $NODE_VMSS \
	--new-capacity 0

# Check if default node is still running
watch kubectl get node

# Delete node if it is still lingering
export REMOVED_NODE=$(kubectl get node -o=jsonpath='{.items[0].metadata.name}')
kubectl delete node $REMOVED_NODE




# make sure all core-dns pods are running in spot node
# may take a while
# BUG: sometimes it will trigger the full price nodepool to scale up again, always double check
watch kubectl get pod -A -o wide

## RUN KUBERNETES COMMANDS
kubectl apply -f azure-vote-back-deployment.yaml

# check deployment
watch kubectl get pod -o wide

# Add DNS to Kubernetes Public IP Address 
export K8S_IP_ID=$(az network public-ip list \
	--subscription $SUBSCRIPTION \
	--resource-group $MC_RESOURCE_GROUP \
    --query '[1].id' -otsv)
az network public-ip update \
	--ids $K8S_IP_ID \
	--dns-name cheapakscluster

# Delete AKS Cluster
az group delete \
	--subscription $SUBSCRIPTION \
    --name $RESOURCE_GROUP \
    --yes --no-wait