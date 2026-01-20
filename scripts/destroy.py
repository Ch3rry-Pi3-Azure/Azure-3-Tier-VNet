import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

DEFAULTS = {
    "location": "eastus2",
    "vnet_name_prefix": "vnet-main",
    "vnet_address_space": ["10.10.0.0/16"],
    "subnet_name_prefix": "snet",
    "subnet_cidrs": {
        "web": "10.10.1.0/24",
        "app": "10.10.2.0/24",
        "db": "10.10.3.0/24",
    },
    "nsg_name_prefix": "nsg",
    "nat_gateway_name_prefix": "nat-vnet",
    "nat_public_ip_name_prefix": "pip-nat",
    "nat_public_ip_sku": "Standard",
    "nat_gateway_sku": "Standard",
    "nat_idle_timeout_in_minutes": 10,
    "nat_subnet_keys": ["app", "web"],
    "app_lb_name_prefix": "lb-app",
    "app_lb_sku": "Standard",
    "app_port": 8080,
    "app_probe_path": "/health",
    "app_vm_name_prefix": "vm-app",
    "app_nic_name_prefix": "nic-app",
    "app_vm_size": "Standard_D2s_v3",
    "app_admin_username": "azureuser",
    "app_subnet_key": "app",
    "sql_server_name_prefix": "sql-vnet",
    "sql_admin_login": "sqladmin",
    "sql_database_name": "vnet-demo",
    "sql_database_sku_name": "GP_S_Gen5_1",
    "sql_max_size_gb": 1,
    "sql_min_capacity": 0.5,
    "sql_auto_pause_delay_in_minutes": 60,
    "sql_public_network_access_enabled": True,
    "sql_zone_redundant": False,
    "sql_allow_azure_services": True,
    "sql_private_dns_zone_name": "privatelink.database.windows.net",
    "sql_private_endpoint_name_prefix": "pe-sql",
    "sql_private_dns_zone_link_name_prefix": "link-sql",
    "sql_private_dns_zone_group_name": "sql-dns",
    "sql_subnet_key": "db",
    "lb_name_prefix": "lb-public",
    "public_ip_name_prefix": "pip-lb",
    "lb_sku": "Standard",
    "public_ip_sku": "Standard",
    "frontend_port": 80,
    "backend_port": 80,
    "probe_path": "/health",
    "vm_name_prefix": "vm-web",
    "nic_name_prefix": "nic-web",
    "vm_size": "Standard_D2s_v3",
    "admin_username": "azureuser",
    "tags": {
        "project": "vnets-subnets",
        "env": "dev",
        "owner": "unknown",
    },
}


def run(cmd):
    print("\n$ " + " ".join(cmd))
    subprocess.check_call(cmd)


def run_capture(cmd):
    print("\n$ " + " ".join(cmd))
    return subprocess.check_output(cmd, text=True).strip()


def run_capture_optional(cmd):
    try:
        return run_capture(cmd)
    except subprocess.CalledProcessError:
        return None


def get_az_exe():
    return "az.cmd" if os.name == "nt" else "az"


def resolve_signed_in_user():
    az_exe = get_az_exe()
    user_login = run_capture_optional([
        az_exe,
        "account",
        "show",
        "--query",
        "user.name",
        "-o",
        "tsv",
    ])
    user_object_id = run_capture_optional([
        az_exe,
        "ad",
        "signed-in-user",
        "show",
        "--query",
        "id",
        "-o",
        "tsv",
    ])
    return user_login or None, user_object_id or None


def hcl_value(value):
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, (list, tuple)):
        rendered = ", ".join(hcl_value(item) for item in value)
        return f"[{rendered}]"
    if isinstance(value, dict):
        rendered = "\n  ".join(f"{key} = {hcl_value(val)}" for key, val in value.items())
        return f"{{\n  {rendered}\n}}"
    escaped = str(value).replace("\"", "\\\"")
    return f"\"{escaped}\""


def write_tfvars(path, items):
    lines = [f"{key} = {hcl_value(value)}" for key, value in items]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def read_tfvars_value(path, key):
    if not path.exists():
        return None
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        name, value = stripped.split("=", 1)
        if name.strip() != key:
            continue
        value = value.strip()
        if value == "null":
            return None
        if value.startswith("\"") and value.endswith("\""):
            return value[1:-1].replace("\\\"", "\"")
        return value
    return None


def parse_csv(value, fallback):
    if not value:
        return fallback
    return [item.strip() for item in value.split(",") if item.strip()]


def parse_bool(value, fallback):
    if value is None:
        return fallback
    normalized = value.strip().lower()
    if normalized in ("1", "true", "yes", "y", "on"):
        return True
    if normalized in ("0", "false", "no", "n", "off"):
        return False
    return fallback


def parse_int(value, fallback):
    if value is None:
        return fallback
    try:
        return int(value)
    except ValueError:
        return fallback


def parse_float(value, fallback):
    if value is None:
        return fallback
    try:
        return float(value)
    except ValueError:
        return fallback


def select_subnet_ids(subnet_ids_by_key, subnet_keys, label):
    selected = []
    missing = []
    for key in subnet_keys:
        subnet_id = subnet_ids_by_key.get(key)
        if subnet_id:
            selected.append(subnet_id)
        else:
            missing.append(key)
    if missing:
        missing_list = ", ".join(missing)
        raise RuntimeError(f"Subnet IDs not found for {label}: {missing_list}.")
    return selected


def load_env_file(path):
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, value = stripped.split("=", 1)
        key = key.strip()
        value = value.strip()
        if key and key not in os.environ:
            os.environ[key] = value


def get_output_optional(tf_dir, output_name):
    output = run_capture_optional(["terraform", f"-chdir={tf_dir}", "output", "-json", output_name])
    if output:
        try:
            value = json.loads(output)
        except json.JSONDecodeError:
            return output
        if value is None or value == "null":
            return None
        if isinstance(value, (dict, list)):
            return json.dumps(value)
        return str(value)
    return get_output_from_state(tf_dir, output_name)


def get_tfstate_path(tf_dir):
    workspace = run_capture_optional(["terraform", f"-chdir={tf_dir}", "workspace", "show"])
    if workspace and workspace != "default":
        workspace_state = tf_dir / "terraform.tfstate.d" / workspace / "terraform.tfstate"
        if workspace_state.exists():
            return workspace_state
    default_state = tf_dir / "terraform.tfstate"
    if default_state.exists():
        return default_state
    return None


def get_output_from_state(tf_dir, output_name):
    state_path = get_tfstate_path(tf_dir)
    if not state_path or not state_path.exists():
        return None
    try:
        state = json.loads(state_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None
    outputs = state.get("outputs", {})
    if output_name not in outputs:
        return None
    value = outputs[output_name].get("value")
    if value is None or value == "null":
        return None
    if isinstance(value, (dict, list)):
        return json.dumps(value)
    return str(value)


def resolve_tags():
    tags = dict(DEFAULTS["tags"])
    project = os.environ.get("TAG_PROJECT")
    env_name = os.environ.get("TAG_ENV")
    owner = os.environ.get("TAG_OWNER")
    if project:
        tags["project"] = project
    if env_name:
        tags["env"] = env_name
    if owner:
        tags["owner"] = owner
    return tags


def get_vm_admin_password(vm_dir):
    env_password = os.environ.get("VM_ADMIN_PASSWORD")
    if env_password:
        return env_password
    existing = read_tfvars_value(vm_dir / "terraform.tfvars", "admin_password")
    if existing:
        return existing
    raise RuntimeError("VM admin password not found. Set VM_ADMIN_PASSWORD before destroying compute.")


def get_app_admin_password(app_dir):
    env_password = os.environ.get("APP_VM_ADMIN_PASSWORD")
    if env_password:
        return env_password
    existing = read_tfvars_value(app_dir / "terraform.tfvars", "admin_password")
    if existing:
        return existing
    raise RuntimeError("App VM admin password not found. Set APP_VM_ADMIN_PASSWORD before destroying app tier.")


def get_sql_admin_password(sql_dir):
    env_password = os.environ.get("SQL_ADMIN_PASSWORD")
    if env_password:
        return env_password
    existing = read_tfvars_value(sql_dir / "terraform.tfvars", "sql_admin_password")
    if existing:
        return existing
    raise RuntimeError("SQL admin password not found. Set SQL_ADMIN_PASSWORD before destroying SQL.")


def get_sql_admin_login(sql_dir):
    env_login = os.environ.get("SQL_ADMIN_LOGIN")
    if env_login:
        return env_login
    existing = read_tfvars_value(sql_dir / "terraform.tfvars", "sql_admin_login")
    if existing:
        return existing
    return DEFAULTS["sql_admin_login"]


def get_sql_client_ip(sql_dir):
    env_ip = os.environ.get("SQL_CLIENT_IP_ADDRESS")
    if env_ip:
        return env_ip
    return read_tfvars_value(sql_dir / "terraform.tfvars", "client_ip_address")


def get_sql_azuread_admin_login(sql_dir):
    env_login = os.environ.get("AZUREAD_ADMIN_LOGIN")
    if env_login:
        return env_login
    existing = read_tfvars_value(sql_dir / "terraform.tfvars", "azuread_admin_login")
    if existing:
        return existing
    user_login, _ = resolve_signed_in_user()
    return user_login


def get_sql_azuread_admin_object_id(sql_dir):
    env_object_id = os.environ.get("AZUREAD_ADMIN_OBJECT_ID")
    if env_object_id:
        return env_object_id
    existing = read_tfvars_value(sql_dir / "terraform.tfvars", "azuread_admin_object_id")
    if existing:
        return existing
    _, user_object_id = resolve_signed_in_user()
    return user_object_id


def write_vnet_tfvars(vnet_dir, rg_name):
    location = os.environ.get("LOCATION", DEFAULTS["location"])
    vnet_name = os.environ.get("VNET_NAME")
    vnet_name_prefix = os.environ.get("VNET_NAME_PREFIX", DEFAULTS["vnet_name_prefix"])
    address_space = parse_csv(os.environ.get("VNET_ADDRESS_SPACE"), DEFAULTS["vnet_address_space"])
    tags = resolve_tags()
    items = [
        ("resource_group_name", rg_name),
        ("location", location),
        ("vnet_name", vnet_name),
        ("vnet_name_prefix", vnet_name_prefix),
        ("address_space", address_space),
        ("tags", tags),
    ]
    write_tfvars(vnet_dir / "terraform.tfvars", items)


def write_subnet_tfvars(subnet_dir, rg_name, vnet_name, vnet_suffix):
    subnet_name_prefix = os.environ.get("SUBNET_NAME_PREFIX", DEFAULTS["subnet_name_prefix"])
    subnet_name_suffix = os.environ.get("SUBNET_NAME_SUFFIX", vnet_suffix)
    subnet_cidrs = dict(DEFAULTS["subnet_cidrs"])
    subnet_cidrs["web"] = os.environ.get("SUBNET_WEB_CIDR", subnet_cidrs["web"])
    subnet_cidrs["app"] = os.environ.get("SUBNET_APP_CIDR", subnet_cidrs["app"])
    subnet_cidrs["db"] = os.environ.get("SUBNET_DB_CIDR", subnet_cidrs["db"])
    items = [
        ("resource_group_name", rg_name),
        ("virtual_network_name", vnet_name),
        ("subnet_name_prefix", subnet_name_prefix),
        ("subnet_name_suffix", subnet_name_suffix),
        ("subnet_cidrs", subnet_cidrs),
    ]
    write_tfvars(subnet_dir / "terraform.tfvars", items)


def write_nsg_tfvars(nsg_dir, rg_name, subnet_ids_by_key):
    location = os.environ.get("LOCATION", DEFAULTS["location"])
    subnet_cidrs = dict(DEFAULTS["subnet_cidrs"])
    subnet_cidrs["web"] = os.environ.get("SUBNET_WEB_CIDR", subnet_cidrs["web"])
    subnet_cidrs["app"] = os.environ.get("SUBNET_APP_CIDR", subnet_cidrs["app"])
    subnet_cidrs["db"] = os.environ.get("SUBNET_DB_CIDR", subnet_cidrs["db"])
    nsg_name_prefix = os.environ.get("NSG_NAME_PREFIX", DEFAULTS["nsg_name_prefix"])
    tags = resolve_tags()
    items = [
        ("resource_group_name", rg_name),
        ("location", location),
        ("subnet_ids_by_key", subnet_ids_by_key),
        ("subnet_cidrs", subnet_cidrs),
        ("nsg_name_prefix", nsg_name_prefix),
        ("tags", tags),
    ]
    write_tfvars(nsg_dir / "terraform.tfvars", items)


def write_nat_tfvars(nat_dir, rg_name, subnet_ids):
    location = os.environ.get("LOCATION", DEFAULTS["location"])
    nat_gateway_name = os.environ.get("NAT_GATEWAY_NAME")
    nat_gateway_name_prefix = os.environ.get("NAT_GATEWAY_NAME_PREFIX", DEFAULTS["nat_gateway_name_prefix"])
    public_ip_name = os.environ.get("NAT_PUBLIC_IP_NAME")
    public_ip_name_prefix = os.environ.get("NAT_PUBLIC_IP_NAME_PREFIX", DEFAULTS["nat_public_ip_name_prefix"])
    public_ip_sku = os.environ.get("NAT_PUBLIC_IP_SKU", DEFAULTS["nat_public_ip_sku"])
    nat_gateway_sku = os.environ.get("NAT_GATEWAY_SKU", DEFAULTS["nat_gateway_sku"])
    idle_timeout = parse_int(
        os.environ.get("NAT_IDLE_TIMEOUT_IN_MINUTES"),
        DEFAULTS["nat_idle_timeout_in_minutes"],
    )
    tags = resolve_tags()
    items = [
        ("resource_group_name", rg_name),
        ("location", location),
        ("nat_gateway_name", nat_gateway_name),
        ("nat_gateway_name_prefix", nat_gateway_name_prefix),
        ("public_ip_name", public_ip_name),
        ("public_ip_name_prefix", public_ip_name_prefix),
        ("public_ip_sku", public_ip_sku),
        ("nat_gateway_sku", nat_gateway_sku),
        ("idle_timeout_in_minutes", idle_timeout),
        ("subnet_ids", subnet_ids),
        ("tags", tags),
    ]
    write_tfvars(nat_dir / "terraform.tfvars", items)


def write_app_tfvars(app_dir, rg_name, subnet_id, sql_dir=None):
    location = os.environ.get("LOCATION", DEFAULTS["location"])
    app_port = parse_int(os.environ.get("APP_PORT"), DEFAULTS["app_port"])
    probe_path = os.environ.get("APP_PROBE_PATH", DEFAULTS["app_probe_path"])
    lb_name = os.environ.get("APP_LB_NAME")
    lb_name_prefix = os.environ.get("APP_LB_NAME_PREFIX", DEFAULTS["app_lb_name_prefix"])
    lb_sku = os.environ.get("APP_LB_SKU", DEFAULTS["app_lb_sku"])
    vm_name = os.environ.get("APP_VM_NAME")
    vm_name_prefix = os.environ.get("APP_VM_NAME_PREFIX", DEFAULTS["app_vm_name_prefix"])
    nic_name_prefix = os.environ.get("APP_NIC_NAME_PREFIX", DEFAULTS["app_nic_name_prefix"])
    vm_size = os.environ.get("APP_VM_SIZE", DEFAULTS["app_vm_size"])
    admin_username = os.environ.get("APP_VM_ADMIN_USERNAME", DEFAULTS["app_admin_username"])
    admin_password = get_app_admin_password(app_dir)
    sql_server_fqdn = get_output_optional(sql_dir, "sql_server_fqdn") if sql_dir else None
    sql_database_name = get_output_optional(sql_dir, "sql_database_name") if sql_dir else None
    sql_admin_login = get_sql_admin_login(sql_dir) if sql_dir else None
    sql_admin_password = None
    if sql_dir:
        try:
            sql_admin_password = get_sql_admin_password(sql_dir)
        except RuntimeError:
            sql_admin_password = None
    tags = resolve_tags()
    items = [
        ("resource_group_name", rg_name),
        ("location", location),
        ("subnet_id", subnet_id),
        ("app_port", app_port),
        ("probe_path", probe_path),
        ("lb_name", lb_name),
        ("lb_name_prefix", lb_name_prefix),
        ("lb_sku", lb_sku),
        ("vm_name", vm_name),
        ("vm_name_prefix", vm_name_prefix),
        ("nic_name_prefix", nic_name_prefix),
        ("vm_size", vm_size),
        ("admin_username", admin_username),
        ("admin_password", admin_password),
        ("sql_server_fqdn", sql_server_fqdn),
        ("sql_database_name", sql_database_name),
        ("sql_admin_login", sql_admin_login),
        ("sql_admin_password", sql_admin_password),
        ("tags", tags),
    ]
    write_tfvars(app_dir / "terraform.tfvars", items)


def write_sql_tfvars(sql_dir, rg_name, vnet_id, subnet_id):
    location = os.environ.get("LOCATION", DEFAULTS["location"])
    sql_server_name = os.environ.get("SQL_SERVER_NAME")
    sql_server_name_prefix = os.environ.get("SQL_SERVER_NAME_PREFIX", DEFAULTS["sql_server_name_prefix"])
    sql_admin_login = get_sql_admin_login(sql_dir)
    sql_admin_password = get_sql_admin_password(sql_dir)
    azuread_admin_login = get_sql_azuread_admin_login(sql_dir)
    azuread_admin_object_id = get_sql_azuread_admin_object_id(sql_dir)
    database_name = os.environ.get("SQL_DATABASE_NAME", DEFAULTS["sql_database_name"])
    database_sku_name = os.environ.get("SQL_DATABASE_SKU_NAME", DEFAULTS["sql_database_sku_name"])
    max_size_gb = parse_int(os.environ.get("SQL_MAX_SIZE_GB"), DEFAULTS["sql_max_size_gb"])
    min_capacity = parse_float(os.environ.get("SQL_MIN_CAPACITY"), DEFAULTS["sql_min_capacity"])
    auto_pause_delay = parse_int(
        os.environ.get("SQL_AUTO_PAUSE_DELAY_IN_MINUTES"),
        DEFAULTS["sql_auto_pause_delay_in_minutes"],
    )
    public_network_access_enabled = parse_bool(
        os.environ.get("SQL_PUBLIC_NETWORK_ACCESS_ENABLED"),
        DEFAULTS["sql_public_network_access_enabled"],
    )
    zone_redundant = parse_bool(os.environ.get("SQL_ZONE_REDUNDANT"), DEFAULTS["sql_zone_redundant"])
    allow_azure_services = parse_bool(
        os.environ.get("SQL_ALLOW_AZURE_SERVICES"),
        DEFAULTS["sql_allow_azure_services"],
    )
    client_ip_address = get_sql_client_ip(sql_dir)
    private_dns_zone_name = os.environ.get(
        "SQL_PRIVATE_DNS_ZONE_NAME",
        DEFAULTS["sql_private_dns_zone_name"],
    )
    private_endpoint_name_prefix = os.environ.get(
        "SQL_PRIVATE_ENDPOINT_NAME_PREFIX",
        DEFAULTS["sql_private_endpoint_name_prefix"],
    )
    private_dns_zone_link_name_prefix = os.environ.get(
        "SQL_PRIVATE_DNS_ZONE_LINK_NAME_PREFIX",
        DEFAULTS["sql_private_dns_zone_link_name_prefix"],
    )
    private_dns_zone_group_name = os.environ.get(
        "SQL_PRIVATE_DNS_ZONE_GROUP_NAME",
        DEFAULTS["sql_private_dns_zone_group_name"],
    )
    tags = resolve_tags()
    items = [
        ("resource_group_name", rg_name),
        ("location", location),
        ("virtual_network_id", vnet_id),
        ("subnet_id", subnet_id),
        ("sql_server_name", sql_server_name),
        ("sql_server_name_prefix", sql_server_name_prefix),
        ("sql_admin_login", sql_admin_login),
        ("sql_admin_password", sql_admin_password),
        ("azuread_admin_login", azuread_admin_login),
        ("azuread_admin_object_id", azuread_admin_object_id),
        ("database_name", database_name),
        ("database_sku_name", database_sku_name),
        ("max_size_gb", max_size_gb),
        ("min_capacity", min_capacity),
        ("auto_pause_delay_in_minutes", auto_pause_delay),
        ("public_network_access_enabled", public_network_access_enabled),
        ("allow_azure_services", allow_azure_services),
        ("client_ip_address", client_ip_address),
        ("zone_redundant", zone_redundant),
        ("private_dns_zone_name", private_dns_zone_name),
        ("private_endpoint_name_prefix", private_endpoint_name_prefix),
        ("private_dns_zone_link_name_prefix", private_dns_zone_link_name_prefix),
        ("private_dns_zone_group_name", private_dns_zone_group_name),
        ("tags", tags),
    ]
    write_tfvars(sql_dir / "terraform.tfvars", items)


def write_lb_tfvars(lb_dir, rg_name):
    location = os.environ.get("LOCATION", DEFAULTS["location"])
    lb_name = os.environ.get("LB_NAME")
    lb_name_prefix = os.environ.get("LB_NAME_PREFIX", DEFAULTS["lb_name_prefix"])
    public_ip_name = os.environ.get("PUBLIC_IP_NAME")
    public_ip_name_prefix = os.environ.get("PUBLIC_IP_NAME_PREFIX", DEFAULTS["public_ip_name_prefix"])
    lb_sku = os.environ.get("LB_SKU", DEFAULTS["lb_sku"])
    public_ip_sku = os.environ.get("PUBLIC_IP_SKU", DEFAULTS["public_ip_sku"])
    frontend_port = int(os.environ.get("LB_FRONTEND_PORT", DEFAULTS["frontend_port"]))
    backend_port = int(os.environ.get("LB_BACKEND_PORT", DEFAULTS["backend_port"]))
    probe_path = os.environ.get("LB_PROBE_PATH", DEFAULTS["probe_path"])
    tags = resolve_tags()
    items = [
        ("resource_group_name", rg_name),
        ("location", location),
        ("lb_name", lb_name),
        ("lb_name_prefix", lb_name_prefix),
        ("public_ip_name", public_ip_name),
        ("public_ip_name_prefix", public_ip_name_prefix),
        ("lb_sku", lb_sku),
        ("public_ip_sku", public_ip_sku),
        ("frontend_port", frontend_port),
        ("backend_port", backend_port),
        ("probe_path", probe_path),
        ("tags", tags),
    ]
    write_tfvars(lb_dir / "terraform.tfvars", items)


def write_compute_tfvars(compute_dir, rg_name, subnet_id, lb_backend_pool_id, app_tier_url=None):
    location = os.environ.get("LOCATION", DEFAULTS["location"])
    vm_name = os.environ.get("VM_NAME")
    vm_name_prefix = os.environ.get("VM_NAME_PREFIX", DEFAULTS["vm_name_prefix"])
    nic_name_prefix = os.environ.get("NIC_NAME_PREFIX", DEFAULTS["nic_name_prefix"])
    vm_size = os.environ.get("VM_SIZE", DEFAULTS["vm_size"])
    admin_username = os.environ.get("VM_ADMIN_USERNAME", DEFAULTS["admin_username"])
    admin_password = get_vm_admin_password(compute_dir)
    env_app_tier_url = os.environ.get("APP_TIER_URL")
    app_tier_url = env_app_tier_url or app_tier_url
    tags = resolve_tags()
    items = [
        ("resource_group_name", rg_name),
        ("location", location),
        ("subnet_id", subnet_id),
        ("lb_backend_pool_id", lb_backend_pool_id),
        ("app_tier_url", app_tier_url),
        ("vm_name", vm_name),
        ("vm_name_prefix", vm_name_prefix),
        ("nic_name_prefix", nic_name_prefix),
        ("vm_size", vm_size),
        ("admin_username", admin_username),
        ("admin_password", admin_password),
        ("tags", tags),
    ]
    write_tfvars(compute_dir / "terraform.tfvars", items)


def destroy_stack(tf_dir):
    if not tf_dir.exists():
        raise FileNotFoundError(f"Missing Terraform dir: {tf_dir}")
    run(["terraform", f"-chdir={tf_dir}", "init"])
    run(["terraform", f"-chdir={tf_dir}", "destroy", "-auto-approve"])


def state_exists(tf_dir):
    state_path = get_tfstate_path(tf_dir)
    return state_path is not None and state_path.exists()


if __name__ == "__main__":
    try:
        parser = argparse.ArgumentParser(description="Destroy Terraform stacks for the VNets & Subnets project.")
        group = parser.add_mutually_exclusive_group()
        group.add_argument("--rg-only", action="store_true", help="Destroy only the resource group stack")
        group.add_argument("--vnet-only", action="store_true", help="Destroy only the virtual network stack")
        group.add_argument("--subnets-only", action="store_true", help="Destroy only the subnet stack")
        group.add_argument("--nsg-only", action="store_true", help="Destroy only the network security groups stack")
        group.add_argument("--sql-only", action="store_true", help="Destroy only the SQL + private endpoint stack")
        group.add_argument("--nat-only", action="store_true", help="Destroy only the NAT gateway stack")
        group.add_argument("--app-only", action="store_true", help="Destroy only the app tier stack")
        group.add_argument("--lb-only", action="store_true", help="Destroy only the load balancer stack")
        group.add_argument("--compute-only", action="store_true", help="Destroy only the web compute stack")
        args = parser.parse_args()

        repo_root = Path(__file__).resolve().parent.parent
        load_env_file(repo_root / ".env")
        rg_dir = repo_root / "terraform" / "01_resource_group"
        vnet_dir = repo_root / "terraform" / "02_vnet"
        subnets_dir = repo_root / "terraform" / "03_subnets"
        nsg_dir = repo_root / "terraform" / "04_nsg"
        sql_dir = repo_root / "terraform" / "05_private_sql"
        nat_dir = repo_root / "terraform" / "06_nat_gateway"
        app_dir = repo_root / "terraform" / "07_app_tier"
        lb_dir = repo_root / "terraform" / "08_load_balancer"
        compute_dir = repo_root / "terraform" / "09_compute_web"

        if args.rg_only:
            destroy_stack(rg_dir)
            sys.exit(0)

        if args.vnet_only:
            rg_name = get_output_optional(rg_dir, "resource_group_name") or os.environ.get("RESOURCE_GROUP_NAME")
            if not rg_name:
                raise RuntimeError("Resource group name not found for VNet destroy.")
            write_vnet_tfvars(vnet_dir, rg_name)
            destroy_stack(vnet_dir)
            sys.exit(0)

        if args.subnets_only:
            rg_name = get_output_optional(rg_dir, "resource_group_name") or os.environ.get("RESOURCE_GROUP_NAME")
            if not rg_name:
                raise RuntimeError("Resource group name not found for subnet destroy.")
            vnet_name = get_output_optional(vnet_dir, "virtual_network_name") or os.environ.get("VNET_NAME")
            if not vnet_name:
                raise RuntimeError("Virtual network name not found for subnet destroy.")
            vnet_suffix = get_output_optional(vnet_dir, "vnet_name_suffix")
            write_subnet_tfvars(subnets_dir, rg_name, vnet_name, vnet_suffix)
            destroy_stack(subnets_dir)
            sys.exit(0)

        if args.nsg_only:
            rg_name = get_output_optional(rg_dir, "resource_group_name") or os.environ.get("RESOURCE_GROUP_NAME")
            if not rg_name:
                raise RuntimeError("Resource group name not found for NSG destroy.")
            subnet_ids_json = get_output_optional(subnets_dir, "subnet_ids_by_key")
            if not subnet_ids_json:
                raise RuntimeError("Subnet IDs not found for NSG destroy.")
            subnet_ids_by_key = json.loads(subnet_ids_json)
            write_nsg_tfvars(nsg_dir, rg_name, subnet_ids_by_key)
            destroy_stack(nsg_dir)
            sys.exit(0)

        if args.sql_only:
            rg_name = get_output_optional(rg_dir, "resource_group_name") or os.environ.get("RESOURCE_GROUP_NAME")
            if not rg_name:
                raise RuntimeError("Resource group name not found for SQL destroy.")
            vnet_id = get_output_optional(vnet_dir, "virtual_network_id")
            if not vnet_id:
                raise RuntimeError("Virtual network ID not found for SQL destroy.")
            subnet_ids_json = get_output_optional(subnets_dir, "subnet_ids_by_key")
            if not subnet_ids_json:
                raise RuntimeError("Subnet IDs not found for SQL destroy.")
            subnet_ids_by_key = json.loads(subnet_ids_json)
            subnet_key = os.environ.get("SQL_SUBNET_KEY", DEFAULTS["sql_subnet_key"])
            subnet_id = subnet_ids_by_key.get(subnet_key)
            if not subnet_id:
                raise RuntimeError(f"Subnet ID not found for SQL destroy (key: {subnet_key}).")
            write_sql_tfvars(sql_dir, rg_name, vnet_id, subnet_id)
            destroy_stack(sql_dir)
            sys.exit(0)

        if args.nat_only:
            rg_name = get_output_optional(rg_dir, "resource_group_name") or os.environ.get("RESOURCE_GROUP_NAME")
            if not rg_name:
                raise RuntimeError("Resource group name not found for NAT destroy.")
            subnet_ids_json = get_output_optional(subnets_dir, "subnet_ids_by_key")
            if not subnet_ids_json:
                raise RuntimeError("Subnet IDs not found for NAT destroy.")
            subnet_ids_by_key = json.loads(subnet_ids_json)
            nat_subnet_keys = parse_csv(os.environ.get("NAT_SUBNET_KEYS"), DEFAULTS["nat_subnet_keys"])
            subnet_ids = select_subnet_ids(subnet_ids_by_key, nat_subnet_keys, "NAT destroy")
            write_nat_tfvars(nat_dir, rg_name, subnet_ids)
            destroy_stack(nat_dir)
            sys.exit(0)

        if args.app_only:
            rg_name = get_output_optional(rg_dir, "resource_group_name") or os.environ.get("RESOURCE_GROUP_NAME")
            if not rg_name:
                raise RuntimeError("Resource group name not found for app tier destroy.")
            subnet_ids_json = get_output_optional(subnets_dir, "subnet_ids_by_key")
            if not subnet_ids_json:
                raise RuntimeError("Subnet IDs not found for app tier destroy.")
            subnet_ids_by_key = json.loads(subnet_ids_json)
            subnet_key = os.environ.get("APP_SUBNET_KEY", DEFAULTS["app_subnet_key"])
            subnet_id = subnet_ids_by_key.get(subnet_key)
            if not subnet_id:
                raise RuntimeError(f"Subnet ID not found for app tier destroy (key: {subnet_key}).")
            write_app_tfvars(app_dir, rg_name, subnet_id, sql_dir)
            destroy_stack(app_dir)
            sys.exit(0)

        if args.lb_only:
            rg_name = get_output_optional(rg_dir, "resource_group_name") or os.environ.get("RESOURCE_GROUP_NAME")
            if not rg_name:
                raise RuntimeError("Resource group name not found for load balancer destroy.")
            write_lb_tfvars(lb_dir, rg_name)
            destroy_stack(lb_dir)
            sys.exit(0)

        if args.compute_only:
            rg_name = get_output_optional(rg_dir, "resource_group_name") or os.environ.get("RESOURCE_GROUP_NAME")
            if not rg_name:
                raise RuntimeError("Resource group name not found for compute destroy.")
            subnet_ids_json = get_output_optional(subnets_dir, "subnet_ids_by_key")
            if not subnet_ids_json:
                raise RuntimeError("Subnet IDs not found for compute destroy.")
            subnet_ids_by_key = json.loads(subnet_ids_json)
            web_subnet_id = subnet_ids_by_key.get("web")
            if not web_subnet_id:
                raise RuntimeError("Web subnet ID not found for compute destroy.")
            lb_backend_pool_id = get_output_optional(lb_dir, "lb_backend_pool_id")
            if not lb_backend_pool_id:
                raise RuntimeError("Load balancer backend pool ID not found for compute destroy.")
            app_lb_private_ip = get_output_optional(app_dir, "app_lb_private_ip")
            app_tier_url = f"http://{app_lb_private_ip}:8080" if app_lb_private_ip else None
            write_compute_tfvars(compute_dir, rg_name, web_subnet_id, lb_backend_pool_id, app_tier_url)
            destroy_stack(compute_dir)
            sys.exit(0)

        if state_exists(compute_dir):
            rg_name = get_output_optional(rg_dir, "resource_group_name") or os.environ.get("RESOURCE_GROUP_NAME")
            subnet_ids_json = get_output_optional(subnets_dir, "subnet_ids_by_key")
            lb_backend_pool_id = get_output_optional(lb_dir, "lb_backend_pool_id")
            if rg_name and subnet_ids_json and lb_backend_pool_id:
                subnet_ids_by_key = json.loads(subnet_ids_json)
                web_subnet_id = subnet_ids_by_key.get("web")
                if web_subnet_id:
                    app_lb_private_ip = get_output_optional(app_dir, "app_lb_private_ip")
                    app_tier_url = f"http://{app_lb_private_ip}:8080" if app_lb_private_ip else None
                    write_compute_tfvars(compute_dir, rg_name, web_subnet_id, lb_backend_pool_id, app_tier_url)
            destroy_stack(compute_dir)

        if state_exists(lb_dir):
            rg_name = get_output_optional(rg_dir, "resource_group_name") or os.environ.get("RESOURCE_GROUP_NAME")
            if rg_name:
                write_lb_tfvars(lb_dir, rg_name)
            destroy_stack(lb_dir)

        if state_exists(app_dir):
            rg_name = get_output_optional(rg_dir, "resource_group_name") or os.environ.get("RESOURCE_GROUP_NAME")
            subnet_ids_json = get_output_optional(subnets_dir, "subnet_ids_by_key")
            if rg_name and subnet_ids_json:
                subnet_ids_by_key = json.loads(subnet_ids_json)
                subnet_key = os.environ.get("APP_SUBNET_KEY", DEFAULTS["app_subnet_key"])
                subnet_id = subnet_ids_by_key.get(subnet_key)
                if subnet_id:
                    write_app_tfvars(app_dir, rg_name, subnet_id, sql_dir)
            destroy_stack(app_dir)

        if state_exists(nat_dir):
            rg_name = get_output_optional(rg_dir, "resource_group_name") or os.environ.get("RESOURCE_GROUP_NAME")
            subnet_ids_json = get_output_optional(subnets_dir, "subnet_ids_by_key")
            if rg_name and subnet_ids_json:
                subnet_ids_by_key = json.loads(subnet_ids_json)
                nat_subnet_keys = parse_csv(os.environ.get("NAT_SUBNET_KEYS"), DEFAULTS["nat_subnet_keys"])
                subnet_ids = [subnet_ids_by_key.get(key) for key in nat_subnet_keys if subnet_ids_by_key.get(key)]
                if subnet_ids:
                    write_nat_tfvars(nat_dir, rg_name, subnet_ids)
            destroy_stack(nat_dir)

        if state_exists(sql_dir):
            rg_name = get_output_optional(rg_dir, "resource_group_name") or os.environ.get("RESOURCE_GROUP_NAME")
            vnet_id = get_output_optional(vnet_dir, "virtual_network_id")
            subnet_ids_json = get_output_optional(subnets_dir, "subnet_ids_by_key")
            if rg_name and vnet_id and subnet_ids_json:
                subnet_ids_by_key = json.loads(subnet_ids_json)
                subnet_key = os.environ.get("SQL_SUBNET_KEY", DEFAULTS["sql_subnet_key"])
                subnet_id = subnet_ids_by_key.get(subnet_key)
                if subnet_id:
                    write_sql_tfvars(sql_dir, rg_name, vnet_id, subnet_id)
            destroy_stack(sql_dir)

        if state_exists(nsg_dir):
            rg_name = get_output_optional(rg_dir, "resource_group_name") or os.environ.get("RESOURCE_GROUP_NAME")
            subnet_ids_json = get_output_optional(subnets_dir, "subnet_ids_by_key")
            if rg_name and subnet_ids_json:
                write_nsg_tfvars(nsg_dir, rg_name, json.loads(subnet_ids_json))
            destroy_stack(nsg_dir)

        if state_exists(subnets_dir):
            rg_name = get_output_optional(rg_dir, "resource_group_name") or os.environ.get("RESOURCE_GROUP_NAME")
            vnet_name = get_output_optional(vnet_dir, "virtual_network_name") or os.environ.get("VNET_NAME")
            vnet_suffix = get_output_optional(vnet_dir, "vnet_name_suffix")
            if rg_name and vnet_name:
                write_subnet_tfvars(subnets_dir, rg_name, vnet_name, vnet_suffix)
            destroy_stack(subnets_dir)

        if state_exists(vnet_dir):
            rg_name = get_output_optional(rg_dir, "resource_group_name") or os.environ.get("RESOURCE_GROUP_NAME")
            if rg_name:
                write_vnet_tfvars(vnet_dir, rg_name)
            destroy_stack(vnet_dir)

        destroy_stack(rg_dir)
    except subprocess.CalledProcessError as exc:
        print(f"Command failed: {exc}")
        sys.exit(exc.returncode)
