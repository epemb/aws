import boto3


client = boto3.client('ec2')

def get_all_instances():
    instances = []
    response = client.describe_instances()

    for reservation in response["Reservations"]:
        for instance in reservation["Instances"]:
            instances.append({
                "InstanceId": instance["InstanceId"],                
                "PrivateIpAddress": instance.get("PrivateIpAddress"),
            })

    return instances


def find_instance(identifier, instances):
    for instance in instances:
        if identifier in (instance["InstanceId"], instance["PrivateIpAddress"]):
            return instance
    return None


def remove_instance():
    instances = get_all_instances()
    identifier = input("Enter instance ID or private IP to remove: ").strip()

    instance = find_instance(identifier, instances)
    if instance is None:
        print(f"No instance found matching '{identifier}'")
        return

    client.terminate_instances(InstanceIds=[instance["InstanceId"]])
    print(f"Terminated instance {instance["InstanceId"]}")


if __name__ == "__main__":
    remove_instance()


