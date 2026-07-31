lib: {
  keystoneOptions = {
    full_name = lib.mkOption {
      type = lib.types.str;
      description = "Main user's full name";
    };
  };
}
