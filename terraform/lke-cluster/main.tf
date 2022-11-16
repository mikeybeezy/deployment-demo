provider "google" {
  project     = "scaletific-dev-env-368717"
  credentials = file("vredentials.json")
  region      = "us-central1"
  zone        = "us-central1-c"
}
terraform {
  backend "gcs" {
    bucket = "scaletific-dev"
    prfix  = "terrform/state"
  }
}

resource "google_project_service" "compute" {
  service = "compute.googleapis.com"

}

resource "google_project_service" "container " {
  service = "container.googleapis.com"

}
# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_network#delete_default_routes_on_create
resource "google_compute_network" "main" {
  name                            = "main"
  routing_mode                    = "REGIONAL"
  auto_create_subnetworks         = false
  mtu                             = 1460
  delete_default_routes_on_create = false

  depends_on = [
    google_project_service.compute,
    google_project_service.container

  ]

}

# SUBNETS
resource "google_compute_subnetwork" "private" {
  name                     = "private"
  ip_cidr_range            = "10.0.0.0/18" # kubernetes Nodes will use IP addresses from this range 
  region                   = "us-central1"
  network                  = google_compute_network.main.id
  private_ip_google_access = true
}

# kubernets pods wil use IP addres from the secondary ip range this can also be used for incase we need to open a firewall tp access other VM's in the VPC from kubernetes
secondary_ip_range {
  range_name    = "k8s-pod-range"
  ip_cidr_range = "10.48.0.0/14"
}

# Used to assign IP addresses for cluster IPS and kubernetes service 
secondary_ip_range {
  range_name    = "k8s-service-range"
  ip_cidr_range = "10.48.0.0/14"
}

# ROUTER
# used for VMS without public Ip address to access the internet 

resource "google_compute_router" "router" {
  name    = "router"
  region  = "us-central1"
  network = google_compute_network.main.id

}

# Cloud NAT

resource "google_compute_router_nat" "nat" {
  name   = "nat"
  router = google_compute_router.router.name
  region = "us-central1"

  source_subnetwork_ip_ranges_to_nat = "LIST OF SUBNETWORKS"
  nat_ip_allocate_option             = "MANUAL ONLY"

  subnetwork {
    name                               = google_compute_subnetwork.private.id
    source_subnetwork_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
  nat_ips = [google_compute_address.nat.self_link]
}
resource "google_compute_address" "nat" {
  name         = nat
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"
  depends_on   = [google_project_service.compute]
}

# FIREWALL
resource "google_compute_firewall" "allow-ssh" {
  name    = "allow-ssh"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    portd    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_container_cluster" "primary" {
  name                     = "scaletific-dev"
  location                 = "us-central1"
  remove_default_node_pool = true
  initial_node_count       = 2
  network                  = google_compute_network.main.self_link
  subnetwork               = google_compute_subnetwork.private.self_link
  logging_service          = "logging.googleapis.com/Kubernetes"

}
# //Use the Linode Provider
# provider "linode" {
#   token = var.token
# }

# //Use the linode_lke_cluster resource to create
# //a Kubernetes cluster
# resource "linode_lke_cluster" "cool_linode_cluster" {
#     k8s_version = var.k8s_version
#     label = var.label
#     region = var.region
#     tags = var.tags

#     dynamic "pool" {
#         for_each = var.pools
#         content {
#             type  = pool.value["type"]
#             count = pool.value["count"]
#         }
#     }
# }

# output "kubeconfig" {
#    value = linode_lke_cluster.cool_linode_cluster.kubeconfig
#    sensitive = true
# }

# output "api_endpoints" {
#    value = linode_lke_cluster.cool_linode_cluster.api_endpoints
# }

# output "status" {
#    value = linode_lke_cluster.cool_linode_cluster.status
# }

# output "id" {
#    value = linode_lke_cluster.cool_linode_cluster.id
# }

# output "pool" {
#    value = linode_lke_cluster.cool_linode_cluster.pool
# }
