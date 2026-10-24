output "website_url" {
  value = "http://${aws_s3_bucket_website_configuration.site.website_endpoint}"
}

output "api_url" {
  value = "${aws_api_gateway_stage.main.invoke_url}/get_balance"
}
