# @summary A Puppet environment name: lowercase letters, digits and underscores
type Peadm::Pe_environment = Pattern[/\A[a-z0-9_]+\z/]
