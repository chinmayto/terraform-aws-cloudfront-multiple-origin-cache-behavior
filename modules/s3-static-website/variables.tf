variable "common_tags" {}
variable "naming_prefix" {}
variable "bucket_name" {}
variable "source_files" {}

variable "mime_map" {
  type = map(string)
  default = {
    css         = "text/css"
    html        = "text/html"
    ico         = "image/x-icon"
    png         = "image/png"
    jpeg        = "image/jpeg"
    jpg         = "image/jpeg"
    svg         = "image/svg+xml"
    webmanifest = "application/manifest+json"
    xml         = "application/xml"
  }
}