# ==========================================
# AWS Full Cleanup Script (PowerShell)
# WARNING: This WILL delete almost everything in us-east-1
# ==========================================

param(
    [switch]$Force
)

$region = "us-east-1"

Write-Host "🧹 AWS Full Cleanup Script - Region: $region" -ForegroundColor Yellow
if (-not $Force) {
    $confirm = Read-Host "Type 'yes' to continue (this will delete almost everything!)"
    if ($confirm -ne 'yes') { Write-Host "Cancelled."; exit 0 }
}

# ---------- Helper function: wait for resource to disappear ----------
function Wait-UntilDeleted($resourceCheckScript, $maxRetries=10, $delaySec=5) {
    $i = 0
    while ($i -lt $maxRetries) {
        $res = Invoke-Expression $resourceCheckScript
        if (-not $res) { return }
        Start-Sleep -Seconds $delaySec
        $i++
    }
}

# ---------- EC2 Instances ----------
Write-Host "Terminating EC2 instances..."
$instances = aws ec2 describe-instances --region $region --query "Reservations[].Instances[].InstanceId" --output text
if ($instances) {
    $ids = $instances -split '\s+'
    aws ec2 terminate-instances --region $region --instance-ids $ids
}

# ---------- EBS Volumes ----------
Write-Host "Deleting EBS volumes..."
$vols = (aws ec2 describe-volumes --region $region --query "Volumes[].VolumeId" --output text) -split '\s+'
foreach ($v in $vols) { if ($v) { aws ec2 delete-volume --region $region --volume-id $v } }

# ---------- Snapshots ----------
Write-Host "Deleting Snapshots..."
$snaps = (aws ec2 describe-snapshots --region $region --owner-ids self --query "Snapshots[].SnapshotId" --output text) -split '\s+'
foreach ($s in $snaps) { if ($s) { aws ec2 delete-snapshot --region $region --snapshot-id $s } }

# ---------- Elastic IPs ----------
Write-Host "Releasing Elastic IPs..."
$allocs = (aws ec2 describe-addresses --region $region --query "Addresses[].AllocationId" --output text) -split '\s+'
foreach ($a in $allocs) { if ($a) { aws ec2 release-address --region $region --allocation-id $a } }

# ---------- NAT Gateways ----------
Write-Host "Deleting NAT Gateways..."
$nats = (aws ec2 describe-nat-gateways --region $region --query "NatGateways[].NatGatewayId" --output text) -split '\s+'
foreach ($n in $nats) { if ($n) { aws ec2 delete-nat-gateway --region $region --nat-gateway-id $n } }
# Wait a bit for NAT deletion
Start-Sleep -Seconds 15

# ---------- Internet Gateways ----------
Write-Host "Deleting Internet Gateways..."
$igws = (aws ec2 describe-internet-gateways --region $region --query "InternetGateways[].InternetGatewayId" --output text) -split '\s+'
foreach ($igw in $igws) {
    if (-not $igw) { continue }
    $vpcid = aws ec2 describe-internet-gateways --region $region --internet-gateway-ids $igw --query "InternetGateways[].Attachments[].VpcId" --output text
    if ($vpcid) { aws ec2 detach-internet-gateway --region $region --internet-gateway-id $igw --vpc-id $vpcid }
    aws ec2 delete-internet-gateway --region $region --internet-gateway-id $igw
}

# ---------- Subnets ----------
Write-Host "Deleting Subnets..."
$subs = (aws ec2 describe-subnets --region $region --query "Subnets[].SubnetId" --output text) -split '\s+'
foreach ($sub in $subs) { if ($sub) { aws ec2 delete-subnet --region $region --subnet-id $sub } }

# ---------- Route Tables ----------
Write-Host "Deleting Route Tables (non-main)..."
$rts = (aws ec2 describe-route-tables --region $region --query "RouteTables[?Associations[?Main!=true]].RouteTableId" --output text) -split '\s+'
foreach ($rt in $rts) { if ($rt) { aws ec2 delete-route-table --region $region --route-table-id $rt } }

# ---------- Security Groups ----------
Write-Host "Deleting Security Groups (non-default)..."
$sgrps = (aws ec2 describe-security-groups --region $region --query "SecurityGroups[?GroupName!='default'].GroupId" --output text) -split '\s+'
foreach ($sg in $sgrps) { if ($sg) { aws ec2 delete-security-group --region $region --group-id $sg } }

# ---------- Customer-managed Prefix Lists ----------
Write-Host "Deleting Customer-managed Prefix Lists..."
$pls = (aws ec2 describe-managed-prefix-lists --region $region --query "PrefixLists[?OwnerId=='self'].PrefixListId" --output text) -split '\s+'
foreach ($pl in $pls) { if ($pl) { aws ec2 delete-managed-prefix-list --region $region --prefix-list-id $pl } }

# ---------- VPCs ----------
Write-Host "Deleting VPCs..."
$vpcs = (aws ec2 describe-vpcs --region $region --query "Vpcs[].VpcId" --output text) -split '\s+'
foreach ($vpc in $vpcs) {
    if ($vpc) { aws ec2 delete-vpc --region $region --vpc-id $vpc }
}

# ---------- S3 Buckets ----------
Write-Host "Deleting S3 buckets (global)..."
$buckets = (aws s3api list-buckets --query "Buckets[].Name" --output text) -split '\s+'
foreach ($b in $buckets) { if ($b) { aws s3 rb "s3://$b" --force } }

# ---------- Lambda Functions ----------
Write-Host "Deleting Lambda functions..."
$lambdas = (aws lambda list-functions --region $region --query "Functions[].FunctionName" --output text) -split '\s+'
foreach ($l in $lambdas) { if ($l) { aws lambda delete-function --region $region --function-name $l } }

# ---------- RDS Instances ----------
Write-Host "Deleting RDS instances..."
$rds = (aws rds describe-db-instances --region $region --query "DBInstances[].DBInstanceIdentifier" --output text) -split '\s+'
foreach ($db in $rds) { if ($db) { aws rds delete-db-instance --region $region --db-instance-identifier $db --skip-final-snapshot } }

# ---------- ECS Clusters ----------
Write-Host "Deleting ECS clusters..."
$clusters = (aws ecs list-clusters --region $region --query "clusterArns[]" --output text) -split '\s+'
foreach ($c in $clusters) { if ($c) { aws ecs delete-cluster --region $region --cluster $c } }

Write-Host "🎉 Cleanup done for region $region. Verify in AWS Console." -ForegroundColor Green
