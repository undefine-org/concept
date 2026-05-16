defmodule Concept.Knowledge.ProfilesTest do
  use ExUnit.Case, async: true

  alias Concept.Knowledge.{Profile, Profiles}

  describe "Profiles.list/0" do
    test "returns 6 profile structs" do
      profiles = Profiles.list()

      assert length(profiles) == 6
      assert Enum.all?(profiles, &match?(%Profile{}, &1))

      names = Enum.map(profiles, & &1.name)
      assert :fast in names
      assert :default in names
      assert :thorough in names
      assert :outline in names
      assert :contradict in names
      assert :intent in names
    end
  end

  describe "Profiles.get/1" do
    test "returns expected fields for :fast profile" do
      profile = Profiles.get(:fast)

      assert %Profile{} = profile
      assert profile.name == :fast
      assert profile.description == "Cheap chat. No rewrite, no rerank, no ground."
      assert profile.rewrite? == false
      assert profile.search == [mode: :semantic, limit: 6]
      assert profile.rerank? == false
      assert profile.answer == [model: "google:gemini-2.5-flash-lite"]
      assert profile.ground? == false
      assert profile.tools == [:search_workspace]
      assert profile.loop? == false
    end

    test "returns nil for unknown profile" do
      assert Profiles.get(:unknown) == nil
    end
  end

  describe "Profiles.get!/1" do
    test "returns profile for known name" do
      profile = Profiles.get!(:default)
      assert profile.name == :default
    end

    test "raises ArgumentError for unknown profile" do
      assert_raise ArgumentError, ~r/unknown profile: :unknown/, fn ->
        Profiles.get!(:unknown)
      end
    end
  end

  describe "Profile.to_ash_ai_opts/1" do
    test "returns model and tools for :thorough profile" do
      profile = Profiles.get!(:thorough)
      opts = Profile.to_ash_ai_opts(profile)

      assert opts[:model] == "google:gemini-2.5-pro"
      assert opts[:tools] == [:search_workspace, :answer_question, :summarize_page]
    end
  end

  describe "Profile.to_pipeline_opts/1" do
    test "returns Arcana.Pipeline compatible options" do
      profile = Profiles.get!(:thorough)
      opts = Profile.to_pipeline_opts(profile)

      assert opts[:search_mode] == :hybrid
      assert opts[:search_limit] == 12
      assert opts[:rerank?] == true
      assert opts[:rewrite?] == true
      assert opts[:ground?] == true
    end
  end

  describe "compile-time validation" do
    test "bad model string fails at compile time" do
      bad_code = """
      defmodule BadProfiles do
        use Concept.Knowledge.ProfileBuilder

        profile :bad do
          description "Invalid model"
          answer model: "openai:gpt-4"
        end
      end
      """

      assert_raise Spark.Error.DslError, ~r/Invalid model string.*openai:gpt-4/s, fn ->
        Code.compile_string(bad_code)
      end
    end

    test "valid Gemini model strings compile successfully" do
      valid_models = [
        "google:gemini-2.5-flash",
        "google:gemini-2.5-pro",
        "google:gemini-2.5-flash-lite",
        "google:gemini-3.0-pro-preview",
        "google:gemini-embedding-1"
      ]

      for model <- valid_models do
        code = """
        defmodule ValidProfile#{:erlang.phash2(model)} do
          use Concept.Knowledge.ProfileBuilder

          profile :valid do
            answer model: "#{model}"
          end
        end
        """

        # Should not raise
        assert [{_module, _}] = Code.compile_string(code)
      end
    end
  end
end
