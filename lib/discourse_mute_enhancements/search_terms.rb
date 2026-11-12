# frozen_string_literal: true

module DiscourseMuteEnhancements
  # Splits a search term into words, so the search filters can tell what the search asks for.
  module SearchTerms
    # Same tokenizer as Search#process_advanced_search!.
    WORD_SCANNER = /(([^" \t\n\x0B\f\r]+)?(("[^"]+")?))/

    # The words of a search term, cleaned the way core cleans them before matching its advanced
    # filters.
    def self.words(term)
      term.to_s.scan(WORD_SCANNER).filter_map { |(word, _)| word.presence&.gsub(/["']/, "") }
    end
  end
end
