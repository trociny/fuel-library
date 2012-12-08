# add nat tables for nodes range
class cobbler::nat(
  $nat_range = undef,
) {

  Exec  {path => '/usr/bin:/bin:/usr/sbin:/sbin'}

  exec { 'enable_forwarding':
    command => 'echo 1 > /proc/sys/net/ipv4/ip_forward',
    unless  => 'cat /proc/sys/net/ipv4/ip_forward | grep -q 1',
  }

  case $::operatingsystem {
    /(?i)(centos|redhat)/: {
      exec { 'enable_nat_all':
        command => "iptables -t nat -I POSTROUTING 1 \
                    -s ${nat_range}/24 ! -d ${nat_range}/24 -j MASQUERADE; \
                    /etc/init.d/iptables save",
        unless  => "iptables -t nat -S POSTROUTING | grep -q \"^-A POSTROUTING \
                   -s ${nat_range}/24 ! -d ${nat_range}/24 -j MASQUERADE\""
      }

      exec { 'enable_nat_filter':
        command => 'iptables -t filter -I FORWARD 1 -j ACCEPT; \
                   /etc/init.d/iptables save',
        unless  => 'iptables -t filter -S FORWARD | grep -q "^-A FORWARD \
                   -j ACCEPT"'
      }

      exec { 'save_ipv4_forward':
        command => 'sed -i --follow-symlinks -e "/net\.ipv4\.ip_forward/d" \
                   /etc/sysctl.conf && echo "net.ipv4.ip_forward = 1" >> \
                   /etc/sysctl.conf',
        unless  => 'grep -q "^\s*net\.ipv4\.ip_forward = 1" /etc/sysctl.conf',
      }
    }
    /(?i)(debian|ubuntu)/: {
      # In order to save these rules and to make them raising on
      #  boot you supposed to
      # define to resources File["/etc/network/if-post-down.d/iptablessave"]
      # and File["/etc/network/if-pre-up.d/iptablesload"].
      #  Those two resources already
      # defined in cobbler::iptables class, so if you use default init.pp file
      # you already have those files defined

      exec { 'enable_nat_all':
        command => "iptables -t nat -I POSTROUTING 1 \
                    -s ${nat_range}/24 ! -d ${nat_range}/24 -j MASQUERADE; \
                    iptables-save -c > /etc/iptables.rules",
        unless  => "iptables -t nat -S POSTROUTING | grep -q \"^-A POSTROUTING \
                   -s ${nat_range}/24 ! -d ${nat_range}/24 -j MASQUERADE\""
      }

      exec { 'enable_nat_filter':
        command => 'iptables -t filter -I FORWARD 1 -j ACCEPT; \
                   iptables-save -c > /etc/iptables.rules',
        unless  => 'iptables -t filter -S FORWARD | grep -q "^-A \
                   FORWARD -j ACCEPT"'
      }

      # it is for the sake of raising up forwarding mode on boot
      file { '/etc/sysctl.d/60-ipv4_forward.conf' :
        content => 'net.ipv4.ip_forward = 1',
        owner   => root,
        group   => root,
        mode    => '0644',
      }
    }
    default: {}
  }
}
