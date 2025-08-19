output "nix-builder" {
  value = "${module.nix-builder.ct_id}: ${module.nix-builder.ct_address.v4[0]} ${module.nix-builder.ct_address.v6[0]}"
}

output "dns-server" {
  value = "${module.dns-server.ct_id}: ${module.dns-server.ct_address.v4[0]} ${module.dns-server.ct_address.v6[0]}"
}

output "actualbudget" {
  value = "${module.actualbudget.ct_id}: ${module.actualbudget.ct_address.v4[0]} ${module.actualbudget.ct_address.v6[0]}"
}

output "sabnzbd" {
  value = "${module.sabnzbd.ct_id}: ${module.sabnzbd.ct_address.v4[0]} ${module.sabnzbd.ct_address.v6[0]}"
}

output "homepage" {
  value = "${module.homepage.ct_id}: ${module.homepage.ct_address.v4[0]} ${module.homepage.ct_address.v6[0]}"
}

output "plex-server" {
  value = "${module.plex-server.ct_id}: ${module.plex-server.ct_address.v4[0]} ${module.plex-server.ct_address.v6[0]}"
}