#!/usr/bin/env python3

from ansible.module_utils.basic import AnsibleModule
import subprocess
import re
import yaml
import json
import sys

def get_running_containers():
    """Fetch the list of running Docker containers with their image names."""
    try:
        containers = subprocess.run(
            ["docker", "ps", "-q"],
            capture_output=True,
            text=True,
            check=True
        )
        container_ids = containers.stdout.strip().split("\n") if containers.stdout else []

        result = subprocess.run(
            # get image id and tag
            ["docker", "inspect", "--format", "'{{.Name}} {{.Config.Image}} {{.Id}}'", *container_ids],
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip().split("\n") if result.stdout else []
    except subprocess.CalledProcessError as e:
        return {"error": f"Error fetching Docker containers: {e}"}

def identify_type(image_name):
    """Identify the container type based on the image name."""
    if re.search(r'postgres', image_name, re.IGNORECASE):
        return 'postgres'
    elif re.search(r'mysql', image_name, re.IGNORECASE):
        return 'mysql'
    elif re.search(r'redis', image_name, re.IGNORECASE):
        return 'redis'
    elif re.search(r'mongo', image_name, re.IGNORECASE):
        return 'mongodb'
    elif re.search(r'mariadb', image_name, re.IGNORECASE):
        return 'mariadb'
    else:
        return 'unknown'

def get_env_variables(container_name):
    """Fetch environment variables from a Docker container."""
    try:
        result = subprocess.run(
            ["docker", "inspect", container_name], 
            capture_output=True, 
            text=True,
            check=True
        )
        container_info = json.loads(result.stdout)
        env_list = container_info[0]['Config']['Env']
        return {item.split('=')[0]: item.split('=')[1] for item in env_list}
    except subprocess.CalledProcessError as e:
        print(f"Error fetching environment variables for {container_name}: {e}", file=sys.stderr)
        return {}
    except (IndexError, KeyError, json.JSONDecodeError) as e:
        print(f"Error parsing environment variables for {container_name}: {e}", file=sys.stderr)
        return {}

def get_credentials(env_vars, container_type):
    """Get master user and password from environment variables."""
    user_vars = {
        'postgres': 'POSTGRES_USER',
        'mysql': 'MYSQL_USER',
        'mongodb': 'MONGO_INITDB_ROOT_USERNAME',
        'redis': 'REDIS_USER',
        "mariadb": 'MYSQL_USER'
    }

    password_vars = {
        'postgres': 'POSTGRES_PASSWORD',
        'mysql': 'MYSQL_PASSWORD',
        'mongodb': 'MONGO_INITDB_ROOT_PASSWORD',
        'redis': 'REDIS_PASSWORD',
        "mariadb": 'MYSQL_PASSWORD'
    }

    master_user = env_vars.get(user_vars.get(container_type, ''), None)
    master_password = env_vars.get(password_vars.get(container_type, ''), None)
    return master_user, master_password


def main():
    module_args = dict(
        output=dict(type='str', required=False, default=None)
    )

    module = AnsibleModule(argument_spec=module_args, supports_check_mode=True)

    output_file = module.params['output']

    # Get running containers with their image names
    containers = get_running_containers()
    if isinstance(containers, dict) and "error" in containers:
        module.fail_json(msg=containers["error"])

    if not containers or containers == ['']:
        module.exit_json(changed=False, msg="No running Docker containers found.", databases=[])

    # Generate structured data
    databases = []
    for entry in containers:
        if entry:
            container_name, image_name, image_id = entry.split(' ')
            image = {
                'name': image_name,
                'id': image_id
            }
            container_type = identify_type(image_name)
            if container_type != 'unknown':
                env_vars = get_env_variables(container_name)
                master_user, master_password = get_credentials(env_vars, container_type)
                databases.append({'name': container_name, 'type': container_type, 'image': image, 'master_user': master_user, 'master_password': master_password})

    result_data = {'databases': databases}
    yaml_output = yaml.dump(result_data, default_flow_style=False, sort_keys=False)

    # Output to file or return as result
    if output_file:
        try:
            with open(output_file, 'w') as file:
                file.write(yaml_output)
            module.exit_json(changed=True, msg=f"YAML output written to {output_file}", databases=databases)
        except IOError as e:
            module.fail_json(msg=f"Error writing to file: {e}")
    else:
        module.exit_json(changed=False, databases=databases, yaml_output=yaml_output)


 

if __name__ == '__main__':
    main()
