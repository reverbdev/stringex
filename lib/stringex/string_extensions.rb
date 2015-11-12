# encoding: UTF-8

module Stringex
  module StringExtensions
    def self.configure(&block)
      Stringex::Configuration::StringExtensions.configure &block
    end

    def self.unconfigure!
      Stringex::Configuration::StringExtensions.unconfigure!
    end

    # These methods are all included into the String class.
    module PublicInstanceMethods
      # Removes specified character from the beginning and/or end of the string and then performs
      # <tt>String#squeeze(character)</tt>, condensing runs of the character within the string.
      #
      # Note: This method has been superceded by ActiveSupport's squish method.
      def collapse(character = " ")
        sub(/^#{character}*/, "").sub(/#{character}*$/, "").squeeze(character)
      end

      # Converts HTML entities into the respective non-accented letters. Examples:
      #
      #   "&aacute;".convert_accented_entities # => "a"
      #   "&ccedil;".convert_accented_entities # => "c"
      #   "&egrave;".convert_accented_entities # => "e"
      #   "&icirc;".convert_accented_entities # => "i"
      #   "&oslash;".convert_accented_entities # => "o"
      #   "&uuml;".convert_accented_entities # => "u"
      #
      # Note: This does not do any conversion of Unicode/ASCII accented-characters. For that
      # functionality please use <tt>to_ascii</tt>.
      def convert_accented_html_entities
        stringex_convert do
          cleanup_accented_html_entities!
        end
      end

      # Converts various common plaintext characters to a more URI-friendly representation.
      # Examples:
      #
      #   "foo & bar".convert_misc_characters # => "foo and bar"
      #   "Chanel #9".convert_misc_characters # => "Chanel number nine"
      #   "user@host".convert_misc_characters # => "user at host"
      #   "google.com".convert_misc_characters # => "google dot com"
      #   "$10".convert_misc_characters # => "10 dollars"
      #   "*69".convert_misc_characters # => "star 69"
      #   "100%".convert_misc_characters # => "100 percent"
      #   "windows/mac/linux".convert_misc_characters # => "windows slash mac slash linux"
      #
      # It allows localization of conversions so you can use it to convert characters into your own language.
      # Example:
      #
      #   I18n.backend.store_translations :de, { :stringex => { :characters => { :and => "und" } } }
      #   I18n.locale = :de
      #   "ich & dich".convert_misc_characters # => "ich und dich"
      #
      # Note: Because this method will convert any & symbols to the string "and",
      # you should run any methods which convert HTML entities (convert_accented_html_entities and convert_miscellaneous_html_entities)
      # before running this method.
      def convert_miscellaneous_characters(options = {})
        stringex_convert(options) do
          normalize_currency!
          translate! :ellipses, :currencies, :abbreviations, :characters, :apostrophes
          cleanup_characters!
        end
      end

      # Converts HTML entities (taken from common Textile/RedCloth formattings) into plain text formats.
      #
      # Note: This isn't an attempt at complete conversion of HTML entities, just those most likely
      # to be generated by Textile.
      def convert_miscellaneous_html_entities
        stringex_convert do
          translate! :html_entities
          cleanup_html_entities!
        end
      end

      # Converts MS Word 'smart punctuation' to ASCII
      #
      def convert_smart_punctuation
        stringex_convert do
          cleanup_smart_punctuation!
        end
      end

      # Converts vulgar fractions from supported HTML entities and Unicode to plain text formats.
      def convert_vulgar_fractions
        stringex_convert do
          translate! :vulgar_fractions
        end
      end

      def convert_unreadable_control_characters
        stringex_convert do
          translate! :unreadable_control_characters
        end
      end

      # Returns the string limited in size to the value of limit.
      def limit(limit = nil, truncate_words = true, whitespace_replacement_token = "-")
        if limit.nil?
          self
        else
          truncate_words == false ? self.whole_word_limit(limit, whitespace_replacement_token) : self[0...limit]
        end
      end

      def whole_word_limit(limit, whitespace_replacement_token = "-")
        whole_words = []
        words = self.split(whitespace_replacement_token)

        words.each do |word|
          if word.size > limit
            break
          else
            whole_words << word
            limit -= (word.size + 1)
          end
        end

        whole_words.join(whitespace_replacement_token)
      end


      # Performs multiple text manipulations. Essentially a shortcut for typing them all. View source
      # below to see which methods are run.
      def remove_formatting(options = {})
        strip_html_tags.
          convert_smart_punctuation.
          convert_accented_html_entities.
          convert_vulgar_fractions.
          convert_unreadable_control_characters.
          convert_miscellaneous_html_entities.
          convert_miscellaneous_characters(options).
          to_ascii.
          # NOTE: String#to_ascii may convert some Unicode characters to ascii we'd already transliterated
          # so we need to do it again just to be safe
          convert_miscellaneous_characters(options).
          collapse
      end

      # Replace runs of whitespace in string. Defaults to a single space but any replacement
      # string may be specified as an argument. Examples:
      #
      #   "Foo       bar".replace_whitespace # => "Foo bar"
      #   "Foo       bar".replace_whitespace("-") # => "Foo-bar"
      def replace_whitespace(replacement = " ")
        gsub(/\s+/, replacement)
      end

      # Removes HTML tags from text.
      # NOTE: This code is simplified from Tobias Luettke's regular expression in Typo[http://typosphere.org].
      def strip_html_tags(leave_whitespace = false)
        string = stringex_convert do
          strip_html_tags!
        end
        leave_whitespace ? string : string.replace_whitespace(' ')
      end

      # Returns the string converted (via Textile/RedCloth) to HTML format
      # or self [with a friendly warning] if Redcloth is not available.
      #
      # Using <tt>:lite</tt> argument will cause RedCloth to not wrap the HTML in a container
      # P element, which is useful behavior for generating header element text, etc.
      # This is roughly equivalent to ActionView's <tt>textilize_without_paragraph</tt>
      # except that it makes RedCloth do all the work instead of just gsubbing the return
      # from RedCloth.
      def to_html(lite_mode = false)
        if defined?(RedCloth)
          if lite_mode
            RedCloth.new(self, [:lite_mode]).to_html
          else
            if self =~ /<pre>/
              RedCloth.new(self).to_html.tr("\t", "")
            else
              RedCloth.new(self).to_html.tr("\t", "").gsub(/\n\n/, "")
            end
          end
        else
          warn "String#to_html was called without RedCloth being successfully required"
          self
        end
      end

      # Create a URI-friendly representation of the string. This is used internally by
      # acts_as_url[link:classes/Stringex/ActsAsUrl/ClassMethods.html#M000012]
      # but can be called manually in order to generate an URI-friendly version of any string.
      def to_url(options = {})
        return self if options[:exclude] && options[:exclude].include?(self)
        options = stringex_default_options.merge(options)
        whitespace_replacement_token = options[:replace_whitespace_with]
        dummy = remove_formatting(options).
                  replace_whitespace(whitespace_replacement_token).
                  collapse(whitespace_replacement_token).
                  limit(options[:limit], options[:truncate_words], whitespace_replacement_token)
        dummy.downcase! unless options[:force_downcase] == false
        dummy
      end

    private

      def stringex_convert(options = {}, &block)
        Localization.convert self, options, &block
      end

      def stringex_default_options
        Stringex::Configuration::StringExtensions.new.settings.marshal_dump
      end
    end

    # These methods are extended onto the String class itself.
    module PublicClassMethods
      # Returns string of random characters with a length matching the specified limit. Excludes 0
      # to avoid confusion between 0 and O.
      def random(limit)
        strong_alphanumerics = %w{
          a b c d e f g h i j k l m n o p q r s t u v w x y z
          A B C D E F G H I J K L M N O P Q R S T U V W X Y Z
          1 2 3 4 5 6 7 8 9
        }
        Array.new(limit, "").collect{strong_alphanumerics[rand(61)]}.join
      end
    end
  end
end
