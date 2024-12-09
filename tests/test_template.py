#!/usr/bin/env python3
import yaml
import os
from jinja2 import Environment, FileSystemLoader, TemplateNotFound, exceptions
import sys
# to print traceback
import traceback

SAMPLE_YAML = "sample_input.yaml"
TEMPLATE_DIR = "roles/docker_install/templates"
TEMPLATES = [
    "backrest-compose.yaml.j2",
    "backrest-config.json.j2"
]


def load_yaml(file):
    """Load and return YAML data from a file."""
    try:
        with open(file, "r") as f:
            return yaml.safe_load(f)
    except FileNotFoundError:
        print(f"Error: YAML file '{file}' not found.")
        sys.exit(1)
    except yaml.YAMLError as e:
        print(f"Error: Failed to parse YAML file '{file}': {e}")
        sys.exit(1)


def jinja_template_test(template_name, data):
    """Render a Jinja2 template with the provided data."""
    try:
        env = Environment(loader=FileSystemLoader(TEMPLATE_DIR))
        template = env.get_template(template_name)
        return template.render(data)
    except TemplateNotFound:
        print(f"Error: Template '{template_name}' not found in '{TEMPLATE_DIR}'.")
        sys.exit(1)
    except exceptions.TemplateSyntaxError as e:
        print(f"Error: Failed to render template '{template_name}': {e}")
        print(f"Error occurred at line {e.lineno}.")
        sys.exit(1)
    except exceptions.TemplateError as e:
        print(f"Error: Failed to render template '{template_name}': {e}")
        print(traceback.format_exc())
        sys.exit(1)


def main():
    data = load_yaml(SAMPLE_YAML)
    os.makedirs("output", exist_ok=True)
    for template in TEMPLATES:
        print(f"Processing template '{template}'...")
        try:
            output = jinja_template_test(template, data)
            output_filename = os.path.basename(template).replace(".j2", "")
            output_path = os.path.join("output", output_filename)
            with open(output_path, "w") as f:
                f.write(output)
            print(f"Generated '{output_path}' successfully.")
        except Exception as e:
            print(f"Error: Failed to process template '{template}': {e}")
            sys.exit(1)


if __name__ == "__main__":
    main()
