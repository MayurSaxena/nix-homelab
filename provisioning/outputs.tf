output "dns-server" {
  value = {
    id    = module.dns-server.ct_id
    addrs = module.dns-server.ct_address
  }
}

output "nix-builder" {
  value = {
    id    = module.nix-builder.ct_id
    addrs = module.nix-builder.ct_address
  }
}