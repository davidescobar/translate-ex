defmodule Translate do
  @translate_api_base_url "https://www.googleapis.com/language/translate/v2"
  @num_translation_attempts 20


  def languages do
    %{ "en" => "English", "es" => "Spanish", "pt-br" => "Brazilian Portuguese",
       "hi" => "Hindi", "zh-cn" => "Chinese (Simplified)" }
  end


  def extract_yaml_value(line) do
    matches = Regex.scan(~r/\s*[^#][\w\-'"]+:\s*(.+)/, line) |> List.flatten
    case matches do
      [ _, value ] -> # Remove any comments from line.
        value |> String.strip |> String.replace(~r/\s*#[^'"]+$/, "")
      _ -> ""
    end
  end


  defp get_translation(phrase, from_lang, to_lang, google_translate_api_key,
                       translation_cache, line_number \\ nil,
                       try_count \\ 1, max_tries \\ @num_translation_attempts) do
    query = URI.encode_query([ q: phrase, source: from_lang, target: to_lang,
                               key: google_translate_api_key, prettyprint: false ])
    url = "#{@translate_api_base_url}?#{query}"
    response =
      try do
        case Agent.get(translation_cache, &(Map.get(&1, phrase))) do
          nil ->
            # Add a staggered delay depending on which line number the term is in so that
            # not all Tasks ping the Google Translate API at the same time.
            delay_ms = if line_number, do: (round(line_number / 100) * 100 |> round) + 2000, else: 0
            if delay_ms > 0, do: :timer.sleep(delay_ms)
            HTTPotion.get(url).body |> :jsx.decode |> List.first

          cached_translation -> { :cached, cached_translation }
        end
      rescue
        HTTPotion.HTTPError -> nil
      end

    case response do
      { :cached, cached_translation } -> "\"#{cached_translation}\""

      { "data", [ {"translations", [[ { "translatedText", translation } ]] } ] } ->
        translation = String.replace(translation, ~r/(&#39;|&quot;)/, "")
        if translation == phrase do
          "\"#{translation}\" # Not translated - all attempts failed or timed out."
        else
          Agent.update(translation_cache, &Map.put(&1, phrase, translation))
          "\"#{translation}\""
        end

      nil when try_count <= max_tries ->
        get_translation(phrase, from_lang, to_lang, google_translate_api_key,
                        translation_cache, line_number, try_count + 1)
        
      _ -> "\"#{phrase}\" # Not translated - all attempts failed or timed out."
    end
  end


  def translate(yaml_file_path, from_lang, to_lang, google_translate_api_key) do
    from_lang_str = if is_atom(from_lang), do: Atom.to_string(from_lang), else: from_lang
    to_lang_str = if is_atom(to_lang), do: Atom.to_string(to_lang), else: to_lang

    if File.regular?(yaml_file_path) do
      :ibrowse.set_max_pipeline_size(@translate_api_base_url, 80, 1_000_000)
      { :ok, translation_cache } = Agent.start(fn -> %{} end)
      tasks =
        case File.read(yaml_file_path) do
          { :ok, data } ->
            for { line, index } <- (data |> String.split("\n", trim: true) |> Enum.with_index) do
              Task.async(fn ->
                cond do
                  (index == 0) && (line =~ ~r/^\s*#/) -> "# The #{languages[to_lang]} file"
                  (String.strip("#{from_lang_str}:") == String.strip(line)) -> "#{to_lang_str}:"
                  true ->
                    value = extract_yaml_value(line)
                    if (value |> String.strip |> String.length) == 0 do
                      line
                    else
                      value_regex =
                        case (Regex.escape(value) <> "\\s*$") |> Regex.compile do
                          { :ok, regex } -> regex
                          _ -> Regex.escape(value)
                        end

                      # Temporarily replace YAML params with "**" so they don't get 'translated'.
                      yaml_var_re = ~r/%\{\S+\}/
                      yaml_vars = Regex.scan(yaml_var_re, value) |> List.flatten
                      translation_no_vars = String.replace(value, yaml_var_re, "**")
                                            |> get_translation(from_lang, to_lang, google_translate_api_key,
                                                               translation_cache, index + 1)
                      translation =
                        Enum.reduce(yaml_vars, translation_no_vars, fn(var, full_translation) ->
                          String.replace(full_translation, "**", var, global: false)
                        end)
                      String.replace(line, value_regex, translation)
                    end
                end
              end)
            end
          { :error, reason } ->
            IO.puts "Could not open #{Path.basename(yaml_file_path)}!"
            IO.puts "Reason: #{reason}"
            []
        end
      if tasks != [] do
        tasks |> Enum.map(&Task.await(&1, 300_000))
              |> Enum.reject(&(String.strip(&1) == ""))
      else
        []
      end
    else
      []
    end
  end

end
