defmodule TranslateTest do
  use ExUnit.Case

  # test "'extract_yaml_value' function returns the value or empty string" do
   # Lines in the format 'key: value'
   # [ "view: Vista", "view: Vista # This is in spanish" ]
   # |> Enum.all? &(assert Translate.extract_yaml_value(&1) == "Vista")

   # Lines in the format 'key:' and comments-only lines '# Just a comment on this line.'
   # [ "key:", "    sub-categories:      ", "# Just a comment on this line." ]
   # |> Enum.all? &(assert Translate.extract_yaml_value(&1) == "")
  # end

end
