# Regenerates the requirements matrix from the compiled RequirementMap.
# Run from the repository root: mix run scripts/render_requirements.exs
File.write!("spec/requirements.md", CharterAgreementProtocol.RequirementMap.render_markdown())
IO.puts("rendered spec/requirements.md")
