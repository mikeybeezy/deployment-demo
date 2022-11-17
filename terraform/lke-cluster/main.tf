provider "google" {
  project     = "scaletific-dev-env-368717"
  credentials = file("credentials.json")
  region      = "us-central1"
  zone        = "us-central1-c"
}
terraform {
  backend "gcs" {
    bucket = "scaletific-terraform-dev-env"
    prefix = "terrform/state"
  }
}

resource "google_project_service" "compute" {
  service = "compute.googleapis.com"

}

resource "google_project_service" "container" {
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

# # kubernets pods wil use IP addres from the secondary ip range this can also be used for incase we need to open a firewall tp access other VM's in the VPC from kubernetes
# secondary_ip_range {
#   range_name    = "k8s-pod-range"
#   ip_cidr_range = "10.48.0.0/14"
# }

# # Used to assign IP addresses for cluster IPS and kubernetes service 
# secondary_ip_range {
#   range_name    = "k8s-service-range"
#   ip_cidr_range = "10.48.0.0/14"
# }

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
    name                    = google_compute_subnetwork.private.id
    source_ip_ranges_to_nat = ["ALL_SUBNETWORKS_ALL_IP_RANGES"]
  }
  nat_ips = [google_compute_address.nat.self_link]
}
resource "google_compute_address" "nat" {
  name         = "nat"
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
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_container_cluster" "primary" {
  name                     = "scaletific-dev"
  location                 = "us-central1-a"
  remove_default_node_pool = true
  initial_node_count       = 2
  network                  = google_compute_network.main.self_link
  subnetwork               = google_compute_subnetwork.private.self_link
  # logging_service          = "logging.googleapis.com/Kubernetes"
  # monitoring_service = "monitoring.googleapis.com/Kubernetes"
  # networking_mode    = "VPC_NATIVE"

  # for multi zonal cluster
  node_locations = [
    "us-central1-b"
  ]

  addons_config {
    http_load_balancing {
      disabled = true
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
  }
  release_channel {
    channel = "REGULAR"
  }

  workload_identity_config {
    workload_pool = "scaletific-dev-env-368717"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "k8s-pod-range"
    services_secondary_range_name = "k8-service-range"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false #set to true if using VPN or bastion host
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }
  # # Jenkins usecase
  # master_authorized_networks_config {
  #   cidr_blocks {
  #     cidr_block = "10.0.0.0/18"
  #     display_name = "private-subnet-w-jenkins"
  #   }
  # }
}

#kubernetes nodes 
resource "google_service_account" "scaletific_k8s_dev" {
  account_id = "scaletific-k8s-dev-env"

}


resource "google_container_node_pool" "general" {
  name       = "general"
  cluster    = google_container_cluster.primary.id
  node_count = 1

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    preemptible  = false
    machine_type = "e2-small"
    labels = {
      role = "general"
    }
    service_account = google_service_account.scaletific-k8s-dev.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

}

resource "google_container_node_pool" "spot" {
  name    = "spot"
  cluster = google_container_cluster.primary.id

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  autoscaling {
    min_node_count = 0
    max_node_count = 10

  }

  node_config {
    preemptible  = true
    machine_type = "e2-small"

    lables = {
      team = "devops"
    }

    taint = [{
      effect = "NO_SCHEDULE"
      key    = "instance_type"
      value  = "spot"
    }]

    service_account = google_service_account.scaletific-k8s-dev.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

}
