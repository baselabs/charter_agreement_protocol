import Config

# Toolchain floor, enforced in-repo rather than trusted to any one laptop's
# PATH: the supported OTP majors are those with precompiled builds for the
# supported Elixir lines AND a :crypto that exposes the ML-DSA atoms the
# revision-3 conformance corpus verifies with (:mldsa44/65/87 arrive in
# OTP 28.1+ with a linked OpenSSL >= 3.5; probed absent on OTP 27.3.4.17 +
# OpenSSL 3.5.5 — see docs/adr/supported-otp-set.md). Aligned with the
# signer sibling's {28, 29}. This set moves in lockstep with the mix.exs
# :elixir range, .tool-versions, and the CI matrix lanes — one commit, all
# four.
supported_otp = ["28", "29"]
running_otp = to_string(:erlang.system_info(:otp_release))

unless running_otp in supported_otp do
  raise "charter_agreement_protocol supports Erlang/OTP #{Enum.join(supported_otp, "/")}; running #{running_otp} (Elixir #{System.version()}, code root #{:code.root_dir()})."
end
