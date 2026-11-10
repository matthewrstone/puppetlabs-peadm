#
# @summary type for the different steps where the peadm::add_database plan can be started
#
type Peadm::AddDatabaseSteps = Enum[
  'init-db-node',
  'replicate-db',
  'update-classification',
  'update-db-settings',
  'cleanup-db',
  'finalize'
]
