output "nix-builder" {
  value = "${module.nix-builder.ct_id}: ${module.nix-builder.ct_address.v4[0]} ${module.nix-builder.ct_address.v6[0]}"
}

output "dns" {
  value = "${module.dns.ct_id}: ${module.dns.ct_address.v4[0]} ${module.dns.ct_address.v6[0]}"
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

output "plex" {
  value = "${module.plex.ct_id}: ${module.plex.ct_address.v4[0]} ${module.plex.ct_address.v6[0]}"
}

output "overseerr" {
  value = "${module.overseerr.ct_id}: ${module.overseerr.ct_address.v4[0]} ${module.overseerr.ct_address.v6[0]}"
}

output "paperless" {
  value = "${module.paperless.ct_id}: ${module.paperless.ct_address.v4[0]} ${module.paperless.ct_address.v6[0]}"
}

output "minecraft" {
  value = "${module.minecraft.ct_id}: ${module.minecraft.ct_address.v4[0]} ${module.minecraft.ct_address.v6[0]}"
}

output "files" {
  value = "${module.files.ct_id}: ${module.files.ct_address.v4[0]} ${module.files.ct_address.v6[0]}"
}

output "caddy" {
  value = "${module.caddy.ct_id}: ${module.caddy.ct_address.v4[0]} ${module.caddy.ct_address.v6[0]}"
}

output "beszel-hub" {
  value = "${module.beszel-hub.ct_id}: ${module.beszel-hub.ct_address.v4[0]} ${module.beszel-hub.ct_address.v6[0]}"
}

output "servarr" {
  value = "${module.servarr.ct_id}: ${module.servarr.ct_address.v4[0]} ${module.servarr.ct_address.v6[0]}"
}

output "yamtrack" {
  value = "${module.yamtrack.ct_id}: ${module.yamtrack.ct_address.v4[0]} ${module.yamtrack.ct_address.v6[0]}"
}

output "trek" {
  value = "${module.trek.ct_id}: ${module.trek.ct_address.v4[0]} ${module.trek.ct_address.v6[0]}"
}

output "dc01" {
  value = "${module.dc01.vm_id}: ${join(" ", module.dc01.vm_address.v4)}"
}

output "kali01" {
  value = "${module.kali01.vm_id}: ${join(" ", module.kali01.vm_address.v4)}"
}

output "ctf01" {
  value = "${module.ctf01.vm_id}: ${join(" ", module.ctf01.vm_address.v4)}"
}

output "flare01" {
  value = "${module.flare01.vm_id}: ${join(" ", module.flare01.vm_address.v4)}"
}
