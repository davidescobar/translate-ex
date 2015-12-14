defmodule Main do 

  def main(args) do
    if Enum.count(args) == 3 do
      [ from_locale, api_key, yaml_folder_path ] = args
      original_yaml_path = Path.join(yaml_folder_path, "#{from_locale}.yml")
      devise_original_yaml_path = Path.join(yaml_folder_path, "devise.#{from_locale}.yml")

      if File.regular?(original_yaml_path) && File.regular?(devise_original_yaml_path) do
        IO.puts "\n"
        start_time = :erlang.now
        language_tasks =
          for { locale, language } <- Enum.reject(Translate.languages, fn {locale, _} -> locale == from_locale end) do
            IO.puts "#{IO.ANSI.cyan}Translating into #{language}...#{IO.ANSI.default_color}"
            Task.async(fn ->
              translations = Translate.translate(original_yaml_path, from_locale, locale, api_key)
              devise_translations = Translate.translate(devise_original_yaml_path,
                                                        from_locale, locale, api_key)
              translated_yaml_file_path = original_yaml_path
                                          |> Path.dirname
                                          |> Path.join("#{locale}.yml")
              devise_translated_yaml_file_path = devise_original_yaml_path
                                                 |> Path.dirname
                                                 |> Path.join("devise.#{locale}.yml")

              File.write(translated_yaml_file_path, Enum.join(translations, "\n"))
              File.write(devise_translated_yaml_file_path, Enum.join(devise_translations, "\n"))              
              IO.puts "#{IO.ANSI.cyan}#{Enum.count(translations) + Enum.count(devise_translations)} term(s) translated to #{language}.#{IO.ANSI.default_color}"
            end)
          end
        language_tasks |> Enum.each(&Task.await(&1, 300_000))
        translation_time_in_seconds = :timer.now_diff(:erlang.now, start_time) / 1.0e6 |> Float.round(2)
        IO.puts "\n#{IO.ANSI.green}Task completed in: #{translation_time_in_seconds} seconds.#{IO.ANSI.default_color}\n"
      else
        IO.puts "\n#{IO.ANSI.red}Could not find '#{original_yaml_path}' or '#{devise_original_yaml_path}'.\n#{IO.ANSI.default_color}"
      end
    else
      IO.puts "\n#{IO.ANSI.cyan}Usage: ./translate [from-locale] [google-translate-api-key] [i18n-yaml-folder-path]\n#{IO.ANSI.default_color}"
    end
  end

end
