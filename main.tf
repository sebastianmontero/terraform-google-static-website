locals {
  # We have to use dashes instead of dots in the access log bucket, because that bucket is not a website
  website_domain_name_dashed = replace(var.website_domain_name, ".", "-")
  # access_log_kms_keys        = var.access_logs_kms_key_name == "" ? [] : [var.access_logs_kms_key_name]
  website_kms_keys           = var.website_kms_key_name == "" ? [] : [var.website_kms_key_name]
  domain_names = concat([var.website_domain_name], var.additional_domain_names)
}


resource "google_storage_bucket" "website" {
  
  project = var.project

  name          = local.website_domain_name_dashed
  location      = var.website_location
  storage_class = var.website_storage_class

  versioning {
    enabled = var.enable_versioning
  }

  website {
    main_page_suffix = var.index_page
    not_found_page   = var.not_found_page
  }

  dynamic "cors" {
    for_each = var.enable_cors ? ["cors"] : []
    content {
      origin          = var.cors_origins
      method          = var.cors_methods
      response_header = var.cors_extra_headers
      max_age_seconds = var.cors_max_age_seconds
    }
  }

  force_destroy = var.force_destroy_website

  dynamic "encryption" {
    for_each = local.website_kms_keys
    content {
      default_kms_key_name = encryption.value
    }
  }

  # labels = var.custom_labels
  # logging {
  #   log_bucket        = google_storage_bucket.access_logs.name
  #   log_object_prefix = var.access_log_prefix != "" ? var.access_log_prefix : local.website_domain_name_dashed
  # }
}

#resource "google_storage_default_object_acl" "website_acl" {
#  bucket = google_storage_bucket.website.name
#  role_entity = ["READER:allUsers"]
#}

resource "google_storage_default_object_access_control" "website_read" {
  bucket = google_storage_bucket.website.name
  role   = "READER"
  entity = "allUsers"
}

resource "google_compute_backend_bucket" "static" {
  project  = var.project
  name        = "${local.website_domain_name_dashed}-bucket"
  bucket_name = google_storage_bucket.website.name
  enable_cdn  = var.enable_cdn
}

# Create HTTPS certificate
resource "google_compute_managed_ssl_certificate" "website_cert" {
  name        = "${local.website_domain_name_dashed}-cert"
  managed {
    domains = local.domain_names
  }
}

module "load_balancer" {
  source = "github.com/gruntwork-io/terraform-google-load-balancer.git//modules/http-load-balancer?ref=v0.3.0"

  name                  = local.website_domain_name_dashed
  project               = var.project
  url_map               = google_compute_url_map.urlmap.self_link
  custom_domain_names   = local.domain_names
  enable_http           = var.enable_http
  enable_ssl            = true
  ssl_certificates      = [google_compute_managed_ssl_certificate.website_cert.self_link]
  custom_labels         = var.custom_labels
}

# ------------------------------------------------------------------------------
# CREATE THE URL MAP WITH THE BACKEND BUCKET AS DEFAULT SERVICE
# ------------------------------------------------------------------------------

resource "google_compute_url_map" "urlmap" {
  provider = google-beta
  project  = var.project

  name        = "${local.website_domain_name_dashed}-url-map"
  description = "URL map for ${local.website_domain_name_dashed}"

  default_service = google_compute_backend_bucket.static.self_link
}

