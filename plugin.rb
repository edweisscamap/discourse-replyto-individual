# name: replyto-individual plugin
# about: A plugin that allows exposure of the sender's email address for functionality
#        similar to GNU/Mailman's Reply_Goes_To_List = Poster
# version: 0.0.1
# authors: Tarek Loubani <tarek@tarek.org>
# license: aGPLv3

PLUGIN_NAME ||= "replyto-individual".freeze


after_initialize do
  Email::MessageBuilder.class_eval do
    attr_reader :template_args

    ALLOW_REPLY_BY_EMAIL_HEADER = 'X-Discourse-Allow-Reply-By-Email'.freeze

       def html_part
      return unless html_override = @opts[:html_override]

      if @template_args[:unsubscribe_instructions].present?
        unsubscribe_instructions = PrettyText.cook(@template_args[:unsubscribe_instructions], sanitize: false).html_safe
        html_override.gsub!("%{unsubscribe_instructions}", unsubscribe_instructions)
      else
        html_override.gsub!("%{unsubscribe_instructions}", "")
      end

      if @template_args[:header_instructions].present?
        header_instructions = PrettyText.cook(@template_args[:header_instructions], sanitize: false).html_safe
        html_override.gsub!("%{header_instructions}", header_instructions)
      else
        html_override.gsub!("%{header_instructions}", "")
      end

      if @template_args[:respond_instructions].present?
        respond_instructions = PrettyText.cook(@template_args[:respond_instructions], sanitize: false).html_safe
        html_override.gsub!("%{respond_instructions}", respond_instructions)
      else
        html_override.gsub!("%{respond_instructions}", "")
      end

      styled = Email::Styles.new(html_override, @opts)
      styled.format_basic
      if style = @opts[:style]
        styled.send("format_#{style}")
      end

      Mail::Part.new do
        content_type 'text/html; charset=UTF-8'
         p = Post.find_by_id @opts[:post_id]
     #   body.prepend("<b>From: #{p.user.name} <#{p.user.email}></b>\n\n")
         body.prepend("<b>From: #{p.user.user_profile.bio_raw}</b>\n\n")
        body styled.to_html
      end
    end
    
    
      def body
      p = Post.find_by_id @opts[:post_id]
      body = @opts[:body]
      body = I18n.t("#{@opts[:template]}.text_body_template", template_args).dup if @opts[:template]
    #  body << "\n\n From: #{p.user.user_profile.bio_raw}\n\n"
      if @template_args[:unsubscribe_instructions].present?
        body << "\n"
        body << @template_args[:unsubscribe_instructions]
      end
       # body.prepend("<b>From: #{p.user.name} <#{p.user.email}></b>\n\n")
          body.prepend("<b>From: #{p.user.user_profile.bio_raw}</b>\n\n")
      body
    end
    
    
    def header_args
      result = {}
      if @opts[:add_unsubscribe_link]
        unsubscribe_url = @template_args[:unsubscribe_url].presence || @template_args[:user_preferences_url]
        result['List-Unsubscribe'] = "<#{unsubscribe_url}>"
      end

      result['X-Discourse-Post-Id']  = @opts[:post_id].to_s  if @opts[:post_id]
      result['X-Discourse-Topic-Id'] = @opts[:topic_id].to_s if @opts[:topic_id]

      # please, don't send us automatic responses...
      result['X-Auto-Response-Suppress'] = 'All'

      if allow_reply_by_email?
        result[ALLOW_REPLY_BY_EMAIL_HEADER] = true
        result['Reply-To'] = reply_by_email_address
        if private_reply?
          result['Reply-To'] = reply_by_email_address
        else
          p = Post.find_by_id @opts[:post_id]
        # result['CC'] = "#{p.user.name} <#{p.user.email}>"
          result['Reply-to'] = reply_by_email_address
        end
      else
        result['Reply-To'] = from_value
      end

      result.merge(Email::MessageBuilder.custom_headers(SiteSetting.email_custom_headers))
    end
  end

  # Fix the Email::Sender method to also insert the reply_key into CC

  Email::Sender.class_eval do
    def set_reply_key(post_id, user_id)
      return unless user_id &&
        post_id &&
        header_value(Email::MessageBuilder::ALLOW_REPLY_BY_EMAIL_HEADER).present?

      # use safe variant here cause we tend to see concurrency issue
      reply_key = PostReplyKey.find_or_create_by_safe!(
        post_id: post_id,
        user_id: user_id
      ).reply_key

      if header_value('Reply-To') =~ /reply_key/i
        @message.header['Reply-To'] =
          header_value('Reply-To').gsub!("%{reply_key}", reply_key)
      end
      if !header_value('CC').blank?
      @message.header['CC'] =
        header_value('CC').gsub!("%{reply_key}", reply_key)
      end
    end
  end
end
