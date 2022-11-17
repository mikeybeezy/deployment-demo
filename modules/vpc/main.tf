locals {
  project = "scaletific-dev-env-368717"
  region  = "us-west2"

}

provider "google" {
  credentials = file("../../terraform/lke-cluster/credentials.json")
  project     = local.project
  region      = local.region

}

module "vpc" {
  source       = "terraform-google-modules/network/google"
  version      = "~> 4.0"
  project_id   = local.project
  network_name = "scaletific-default-vpc"
  routing_mode = "GLOBAL"

  delete_default_internet_gateway_routes = true

  subnets = [
    {
      subnet_name           = "public"
      subnet_ip             = "10.0.0.0/24"
      subnet_region         = "us-west2"
      subnet_private_access = false
      subnet_flow_logs      = false
    },
    {
      subnet_name           = "private"
      subnet_ip             = "10.0.1.0/24"
      subnet_region         = "us-west2"
      subnet_private_access = true
      subnet_flow_logs      = false
    },
  ]

  routes = [
    {
      name              = "egress-internet"
      description       = "Default route through IGW to access internet"
      destination_range = "0.0.0.0/0"
      next_hop_internet = true

    }
  ]


}

# https://github.com/terraform-google-modules/terraform-google-cloud-router
module "cloud_router" {
  source  = "terraform-google-modules/cloud-router/google"
  version = "~> 4.0"

  name    = "scaletific-cloud-router"
  project = local.project
  region  = local.region
  network = module.vpc.network_name
  nats = [{
    name                               = "nat"
    nat_ip_allocate_option             = "AUTO_ONLY"
    source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
    subnetworks = [{
      name                    = "private"
      source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
    }]
  }]
}
