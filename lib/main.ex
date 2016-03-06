defmodule Main do
  use Timex
  alias Translate

  def main([ from_locale, api_key, i18n_folder_path ]) do
    start_time = Date.now
    i18n_files = Translate.get_source_yaml_paths(i18n_folder_path, from_locale)
    if Enum.empty?(i18n_files) do
      IO.puts "No '#{from_locale}' I18n YAML files found!\n"
    else
      into_locales = Translate.get_available_locales
                     |> Map.keys |> Enum.reject(&(&1 == from_locale))
      errors = Translate.translate_files(api_key, from_locale, into_locales, i18n_files)
               |> List.flatten
      end_time = Date.now
      seconds_elapsed = Date.diff(start_time, end_time, :secs) |> abs
      if Enum.empty?(errors) do
        IO.puts "\n#{IO.ANSI.cyan}All i18n files translated successfully.\n"
      else
        IO.puts "\n#{IO.ANSI.red}There were errors:"
        Enum.each(errors, &(&1 |> inspect |> IO.puts))
        IO.puts ""
      end
      IO.puts "Task completed in #{seconds_elapsed} seconds.\n\n"
    end
  end

  def main(_) do
    IO.puts "\n#{IO.ANSI.cyan}Usage: ./translate [from-locale] [google-translate-api-key] [i18n-yaml-folder-path]\n#{IO.ANSI.default_color}"
  end

end
