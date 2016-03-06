defmodule Translate do

  @translate_api_base_url "https://www.googleapis.com/language/translate/v2"
  @num_translation_attempts 20
  @locales %{ "en" => "English", "es" => "Spanish", "de" => "German",
              "hi" => "Hindi", "zh-cn" => "Chinese (simplified)",
              "pt-br" => "Portuguese (Brazil)" }


  def get_available_locales, do: @locales


  def get_source_yaml_paths(i18n_folder_path, for_locale) do
    if File.dir?(i18n_folder_path) do
      File.ls!(i18n_folder_path)
      |> Stream.filter(fn file -> file =~ ~r/\.yml\s*$/i end) # is a .yml file
      |> Stream.filter(fn file -> file =~ ~r/#{for_locale}\./i end) # contains the from locale + "."
      |> Enum.map(fn file -> Path.join(i18n_folder_path, file) end)
    else
      []
    end
  end


  def translate_files(api_key, from_locale, into_locales, i18n_files) do
    for locale <- into_locales, file <- i18n_files do
      Task.async(fn ->
                   { :ok, cached_translations_pid } = Agent.start(fn -> %{} end)
                   translate_file(api_key, from_locale, locale, cached_translations_pid, file)
                 end)
    end |> Enum.map(&Task.await(&1, 300_000))
  end


  defp translate_file(api_key, from_locale, into_locale, cached_translations_pid, i18n_file_path) do
    if File.regular?(i18n_file_path) do
      IO.puts "#{IO.ANSI.cyan}Translating #{Path.basename(i18n_file_path)} into #{@locales[into_locale]}...#{IO.ANSI.default_color}"
      case File.read(i18n_file_path) do
        { :ok, file_data } ->
          translated_lines =
            String.split(file_data, "\n", trim: true)
            |> Stream.with_index
            |> Enum.map(fn { line, index } ->
                          Task.async(fn ->
                            translate_line(api_key, from_locale, into_locale, cached_translations_pid, { index + 1, line })
                            |> String.replace(~r/\s?&quot;/, "\"")
                            |> String.replace(~r/\s?&#39;/, "'")
                          end)
                        end)
            |> Enum.map(&Task.await(&1, 300_000))
          i18n_file_name = Path.basename(i18n_file_path)
          translated_i18n_file_name = String.replace(i18n_file_name, from_locale <> ".", into_locale <> ".")
          translated_file_path = Path.dirname(i18n_file_path) |> Path.join(translated_i18n_file_name)
          case File.write(translated_file_path, translated_lines |> Enum.join("\n")) do
            :ok ->
              IO.puts "Created new file: #{translated_file_path}"
              []

            { :error, reason } ->
              IO.puts "#{translated_file_path}: #{inspect reason}"
              [ (inspect reason) ]
          end

        { :error, reason } ->
          IO.puts "Could not open #{Path.basename(i18n_file_path)}!"
          IO.puts "Reason: #{inspect reason}"
          IO.puts "#{Path.basename(i18n_file_path)}: #{inspect reason}"
          [ (inspect reason) ]
      end
    else
      [ "File '#{i18n_file_path}' does not exist." ]
    end
  end


  defp translate_line(api_key, from_locale, into_locale, cached_translations_pid, { line_number, line }, attempt \\ 1) do
    if attempt <= @num_translation_attempts do
      cond do
        is_from_locale_line(line, from_locale) -> into_locale <> ":"
        is_comment_line(line) -> line
        true ->
          case line |> remove_comments_from_line |> extract_yaml_value do
            nil -> line
            "" -> line
            value ->
              case Agent.get(cached_translations_pid, &(&1[value])) do
                nil ->
                  line_params = get_yaml_params(line)
                  value_to_translate = value |> remove_surrounding_quotes |> substitute_for_yaml_params("**")
                  case get_google_api_translation(api_key, from_locale, into_locale, value_to_translate) do
                    %{ "data" => %{ "translations" => [ %{ "translatedText" => translation } ] } } ->
                      translation_with_params = substitute_yaml_params_for_place_holder(line_params, "**", translation)
                      if translation_with_params == value do
                        delay_from_line_number_in_ms(line_number) |> :timer.sleep
                        translate_line(api_key, from_locale, into_locale,
                                       cached_translations_pid, { line_number, line }, attempt + 1)
                      else
                        Agent.update(cached_translations_pid, &Map.put(&1, value, translation_with_params))
                        String.replace(line, value, add_surrounding_quotes(translation_with_params))
                      end

                    %{ error: _ } ->
                      delay_from_line_number_in_ms(line_number) |> :timer.sleep
                      translate_line(api_key, from_locale, into_locale,
                                     cached_translations_pid, { line_number, line }, attempt + 1)

                    %{ "error" => %{ "message" => _ } } ->
                      delay_from_line_number_in_ms(line_number) |> :timer.sleep
                      translate_line(api_key, from_locale, into_locale,
                                     cached_translations_pid, { line_number, line }, attempt + 1)
                  end

                cached_value ->
                  String.replace(line, value, add_surrounding_quotes(cached_value))
              end
          end
      end
    else
      value = line |> remove_comments_from_line |> extract_yaml_value
      value_with_quotes = add_surrounding_quotes(value)
      String.replace(line, value, value_with_quotes) <> " # Not translated - all attempts failed or timed out."
    end
  end


  defp add_surrounding_quotes(text) do
    trimmed_text = String.strip(text)
    if !String.starts_with?(trimmed_text, [ "\"", "'" ]) and
       !String.ends_with?(trimmed_text, [ "\"", "'" ]) do
      trimmed_text = String.replace(trimmed_text, "\"", "\\\"")
      "\"#{trimmed_text}\""
    else
      trimmed_text
    end
  end


  defp remove_surrounding_quotes(text) do
    text |> String.strip |> String.replace(~r/^["']|["']$/, "")
  end


  defp get_google_api_translation(api_key, from_locale, to_locale, term) do
    params_str = %{ key: api_key, source: from_locale, target: to_locale, q: term }
                 |> URI.encode_query
    case HTTPoison.get("https://www.googleapis.com/language/translate/v2?#{params_str}") do
      { :ok, %HTTPoison.Response{ body: response } } -> Poison.decode!(response)
      { :error, error } -> %{ error: error }
    end
  end


  defp remove_comments_from_line(line) do
    case line |> String.strip |> String.match?(~r/.+#[^'\"]*$/) do
      true -> String.replace(line, ~r/\s*#[^'\"]*$/, "")
      _ -> line
    end
  end


  defp is_comment_line(line) do
    line |> String.lstrip |> String.starts_with?("#")
  end


  defp is_from_locale_line(line, from_locale) do
    (String.strip(from_locale) <> ":") == String.rstrip(line)
  end


  # defp extract_yaml_key(line) when is_binary(line) do
  #   case Regex.run(~r/\s*([^#][\w\-'"]+):\s*.+/, line) do
  #     [ _, key ] -> key
  #     _ -> nil
  #   end
  # end


  defp extract_yaml_value(line) when is_binary(line) do
    case Regex.run(~r/\s*[^#][\w\-'\"]+:\s*(.+)/, line) do
      [ _, value ] -> if String.strip(value) != "", do: value, else: nil
      _ -> nil
    end
  end


  defp get_yaml_params(line) when is_binary(line) do
    Regex.scan(~r/%\{[^\}]*\}/, line) |> List.flatten
  end


  defp substitute_for_yaml_params(line, replacement)
       when is_binary(line) and is_binary(replacement) do
    params = get_yaml_params(line)
    if Enum.empty?(params) do
      line
    else
      Enum.reduce(params,
                  line,
                  fn(param, new_line) -> String.replace(new_line, param, replacement) end)
    end
  end


  defp substitute_yaml_params_for_place_holder([], place_holder, line)
       when is_binary(place_holder) and is_binary(line), do: line

  defp substitute_yaml_params_for_place_holder(params = [ _ | _ ], place_holder, line)
       when is_binary(place_holder) and is_binary(line) do
    Enum.reduce(params, line, fn(param, new_line) ->
                                String.replace(new_line, place_holder, param, global: false)
                              end)
  end


  defp delay_from_line_number_in_ms(line_number) when is_integer(line_number) and (line_number > 0) do
    num_digits = line_number |> to_string |> String.length
    case num_digits do
      1 -> 50
      2 -> 100
      3 when line_number < 250 -> 750
      3 when line_number in 250..749 -> 500
      3 -> 250
      4 when line_number < 2500 -> 750
      4 when line_number in 2500..7499 -> 500
      4 -> 250
      _ -> 1000
    end
  end

end
