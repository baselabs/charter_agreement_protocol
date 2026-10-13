# Materializes the pinned TypeScript verifier source into _build/verifier-source/.
#
#     mix verifier.source            fetch origin, check the pin, materialize
#     mix verifier.source --cached   materialize from the local cache only
#
# What is checked and why: scripts/verifier_source.exs.

Code.require_file("verifier_source.exs", __DIR__)
CharterAgreementProtocol.VerifierSource.run(System.argv())
