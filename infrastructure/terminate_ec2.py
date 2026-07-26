import boto3
import json


client = boto3.client('ec2')

def get_all_instances():
    instances = []
    response = client.describe_instances()

    for reservation in response["Reservations"]:
        for instance in reservation["Instances"]:
            name = None
            for tag in instance.get("Tags", []):
                if tag["Key"] == "Name":
                    name = tag["Value"]
                    break

            instances.append({
                "InstanceId": instance["InstanceId"],
                "Name": name,
                "PrivateIpAddress": instance.get("PrivateIpAddress"),
            })

    return instances


def find_instance(identifier, instances):
    for instance in instances:
        if identifier in (instance["InstanceId"], instance["Name"], instance["PrivateIpAddress"]):
            return instance
    return None


def remove_instance():
    instances = get_all_instances()
    identifier = input("Enter instance name or private IP to remove: ").strip()

    instance = find_instance(identifier, instances)
    if instance is None:
        print(f"No instance found matching '{identifier}'")
        return

    client.terminate_instances(InstanceIds=[instance["InstanceId"]])
    print(f"Terminated instance {instance['InstanceId']} ({instance['Name']})")


if __name__ == "__main__":
    remove_instance()


