#!/usr/bin/python

from ansible.module_utils.basic import AnsibleModule
import subprocess
import json
import re

def get_docker_images():
    """Fetches the list of Docker images with container info."""
    try:
        result = subprocess.run(
            ["docker", "ps", "--format", "{{.ID}} {{.Image}} {{.Names}}"],
            capture_output=True,
            text=True,
            check=True
        )
        containers = []
        for line in result.stdout.strip().split("\n"):
            if line:
                container_id, image, name = line.split(maxsplit=2)
                containers.append({"id": container_id, "image": image, "name": name})
        return containers
    except subprocess.CalledProcessError as e:
        return {"error": f"Failed to fetch Docker containers: {e}"}

def get_container_inspect(container_id):
    """Fetches detailed information about a container."""
    try:
        result = subprocess.run(
            ["docker", "inspect", container_id],
            capture_output=True,
            text=True,
            check=True
        )
        return json.loads(result.stdout)[0]
    except subprocess.CalledProcessError as e:
        return {"error": f"Failed to inspect container {container_id}: {e}"}

def group_services(containers):
    """Groups containers by service dependencies."""
    services = []
    processed = set()

    for container in containers:
        if container["name"] in processed:
            continue

        # Fetch detailed info
        details = get_container_inspect(container["id"])
        
        containers_info = []

        # Extract volumes
        if details.get("Mounts"):
            bind_volumes = []
            named_volumes = []
            for mount in details["Mounts"]:
                if mount["Type"] == "bind":
                    bind_volumes.append(mount["Source"])
                elif mount["Type"] == "volume":
                    named_volumes.append(mount["Name"])

            containers_info.append({
                "name": container["name"],
                "bind_volumes": bind_volumes,
                "named_volumes": named_volumes
            })

        # Simple grouping logic: Containers with similar names
        service_name = re.split(r'[_-]', container["name"])[0]
        related_containers = [
            c for c in containers if c["name"].startswith(service_name)
        ]

        # Process related containers
        for related in related_containers:
            if related["name"] in processed:
                continue
            details = get_container_inspect(related["id"])
            bind_volumes = []
            named_volumes = []
            if details.get("Mounts"):
                for mount in details["Mounts"]:
                    if mount["Type"] == "bind":
                        bind_volumes.append(mount["Source"])
                    elif mount["Type"] == "volume":
                        named_volumes.append(mount["Name"])
            containers_info.append({
                "name": related["name"],
                "bind_volumes": bind_volumes,
                "named_volumes": named_volumes
            })
            processed.add(related["name"])
        # remove duplicates containers (based on name)
        for container in containers_info:
            if container["name"] in processed:
                containers_info.remove(container)

        services.append({
            "title": service_name,
            "containers": containers_info
        })

    

    return services

def main():
    module = AnsibleModule(argument_spec={})
    containers = get_docker_images()
    
    if "error" in containers:
        module.fail_json(msg=containers["error"])

    grouped_services = group_services(containers)
    module.exit_json(changed=False, services=grouped_services)

if __name__ == '__main__':
    main()
