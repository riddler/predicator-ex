# Coveralls configuration
%{
  # Minimum coverage threshold (fails if coverage is below this)
  minimum_coverage: 90.0,

  # Skip files that shouldn't be included in coverage
  skip_files: [
    # Skip generated files
    ~r/priv\//,
    # Skip build artifacts
    ~r/_build\//,
    # Skip deps
    ~r/deps\//,
    # Skip dev mix tasks
    ~r/lib\/mix\/tasks\/quality/,
  ],

  # Coverage output options
  output_dir: "cover/",
  template_path: "cover/coverage.html",

  # Only count lines that can actually be executed
  treat_no_relevant_lines_as_covered: true,
}
