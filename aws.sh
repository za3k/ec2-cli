#!/bin/sh
# A frontend to the AWS command-line tool.
# Prerequisites: aws jq ssh
KEY_NAME=aws # The Amazon name for the key-pair used
KEY_LOCATION=~/.ssh/aws.pem # The local version of the private key
GROUP=${GROUP:-server} # Enables ssh access, which is disabled by default

SSH_USER=ubuntu # Depends on the image. See http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AccessingInstancesLinux.html

REGION=${REGION:-us-west-1}
ARCHITECTURE=${ARCHITECTURE:-amd64}
INSTANCE_TYPE=${INSTANCE_TYPE:-t1.micro}
WAIT_FOR_STATUS=${WAIT_FOR_STATUS:-terminated}

UBUNTU_AMI="$(dirname $0)/ubuntu-ami.sh"
UBUNTU_IMAGE=$("$UBUNTU_AMI" trusty $ARCHITECTURE $REGION)
IMAGE_ID=${IMAGE_ID:-$UBUNTU_IMAGE}

usage() {
    echo "$0 list|ssh|start|terminate|terminate-all|help"
}

require_jq() {
    if ! which 'jq' >/dev/null; then
        echo "jq is required"
        exit 3
    fi
}

find_instance_by_name() {
    INSTANCE_NAME="$1"; shift 1
    aws ec2 describe-instances --filters "Name=tag:Name,Values=${INSTANCE_NAME}" --filters="Name=instance-state-name,Values=pending,running" "$@" | jq -r '.Reservations[].Instances[].InstanceId'
}
find_instance_by_ref() {
    INSTANCE_REF="$1"; shift 1
    case ${INSTANCE_REF} in
        i-*)
            echo ${INSTANCE_REF};;
        *)
            find_instance_by_name ${INSTANCE_REF};;
    esac
}

create_instance() {
    TEMP_FILE=$(mktemp)
    aws ec2 run-instances --image-id ${IMAGE_ID} --count 1 --instance-type ${INSTANCE_TYPE} --key-name ${KEY_NAME} --security-groups ${GROUP} "$@" | tee ${TEMP_FILE} | cat >&2
    INSTANCE_ID=$(cat ${TEMP_FILE} | jq -r '.Instances[].InstanceId')
    rm ${TEMP_FILE}
    echo ${INSTANCE_ID}
}

name_instance() {
    INSTANCE_ID="$1"
    INSTANCE_NAME="$2"
    aws ec2 create-tags --resources ${INSTANCE_ID} --tags Key=Name,Value=${INSTANCE_NAME} >&2
}

terminate_instance() {
    INSTANCE_ID="$1"
    aws ec2 terminate-instances --instance-ids ${instance_id} "$@" >&2
}

if [ $# -gt 0 ]; then
    subcommand="$1"; shift 1
else
    usage; exit 1
fi

case $subcommand in
    list)
        require_jq
        aws ec2 describe-instances --filters "Name=instance-state-name,Values=pending,running,stopped,stopping" "$@" | jq -r '.Reservations[].Instances[] | { id: .InstanceId, name: [.Tags[]? | select(.Key == "Name") | .Value][0]} | if .name then .name else .id end';;
    start)
        if [ $# -gt 0 ]; then
            INSTANCE_NAME="$1"; shift 1
        else
            usage; exit 1
        fi
        INSTANCE_ID=$(create_instance "$@")
        if [ -n ${INSTANCE_NAME} ]; then
            name_instance ${INSTANCE_ID} ${INSTANCE_NAME}
        fi
        echo ${INSTANCE_ID};;
    terminate|stop)
        if [ $# -gt 0 ]; then
            INSTANCE_REF="$1"; shift 1
        else
            usage; exit 1
        fi
        INSTANCE_ID=$(find_instance_by_ref ${INSTANCE_REF})
        terminate_instance ${INSTANCE_ID}
        echo ${INSTANCE_REF};;
    terminate-all|stop-all)
        set -e
        $0 list | xargs -n 1 $0 terminate;;
    ssh)
        if [ $# -gt 0 ]; then
            INSTANCE_REF="$1"; shift 1
        else
            usage; exit 1
        fi
        INSTANCE_ID=$(find_instance_by_ref ${INSTANCE_REF})
        #PUBLIC_DNS=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID | jq -r '.Reservations[].Instances[].PublicDnsName')
        PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID | jq -r '.Reservations[].Instances[].PublicIpAddress')
        echo "SSHing into $PUBLIC_IP (${INSTANCE_REF})..."
        INSECURE_OPTIONS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
        set -x
        exec ssh ${SSH_USER}@${PUBLIC_IP} -i ${KEY_LOCATION} ${INSECURE_OPTIONS[*]} "$@";;
    status)
        if [ $# -gt 0 ]; then
            INSTANCE_REF="$1"; shift 1
        else
            usage; exit 1
        fi
        INSTANCE_ID=$(find_instance_by_ref ${INSTANCE_REF})
        STATUS=$(aws ec2 describe-instances --instance-ids ${INSTANCE_ID} | jq -r ".Reservations[].Instances[].State.Name")
        echo $STATUS
        case ${STATUS} in
            running|pending|stopping|stopped|shutting-down|terminated)
                exit 0;;
            *)
                exit 1;;
        esac;;
    wait)
        if [ $# -gt 0 ]; then
            INSTANCE_REF="$1"; shift 1
        else
            usage; exit 1
        fi
        INSTANCE_STATUS=$WAIT_FOR_STATUS
        if [ $# -gt 0 ]; then
            INSTANCE_STATUS=$1; shift 1
        fi
        INSTANCE_ID=$(find_instance_by_ref ${INSTANCE_REF})
        echo -n "Waiting for '${INSTANCE_STATUS}'..."
        while [ "$($0 status ${INSTANCE_ID})" != ${INSTANCE_STATUS} ]; do
            echo -n "."
            sleep 1
        done
        echo " ready."
        exit 0;;
    ip)
        if [ $# -gt 0 ]; then
            INSTANCE_REF="$1"; shift 1
        else
            usage; exit 1
        fi
        INSTANCE_ID=$(find_instance_by_ref ${INSTANCE_REF})
        PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID | jq -r '.Reservations[].Instances[].PublicIpAddress')
        echo $PUBLIC_IP;;
    help)
        usage; exit 0;;
    *)
        usage; exit 0;;
esac

