# @summary Returns the installer file name from a URL, without query string or fragment
#
# The file name of a PE installer URL is its last path segment. A pre-signed
# URL (for example an S3 one) carries a query string with the signature after
# it, and that must never become part of a log line, an upload path or a
# directory name. The full URL is still the download source; only the name
# derived from it is cleaned.
#
# @param url
#   The installer URL, with or without a query string or fragment
#
# @return [String] The last path segment of the URL, with `?query` and `#fragment` removed
#
# @example A pre-signed URL
#   peadm::installer_tarball_name('https://h/p/puppet-enterprise-2025.12.1-el-9-x86_64.tar.gz?X-Amz-Signature=abc')
#   # => 'puppet-enterprise-2025.12.1-el-9-x86_64.tar.gz'
#
# @example A URL with a fragment
#   peadm::installer_tarball_name('https://h/p/puppet-enterprise-2025.12.1-el-9-x86_64.tar#frag')
#   # => 'puppet-enterprise-2025.12.1-el-9-x86_64.tar'
function peadm::installer_tarball_name(String[1] $url) >> String {
  # The path is everything before the first ? or #. A "/" inside a query value
  # (as in an S3 credential scope) is therefore never mistaken for a path
  # separator.
  $path = $url.split(/[?#]/)[0]
  $path.split('/')[-1]
}
