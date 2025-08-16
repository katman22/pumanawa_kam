module DefaultParkingProfile
  def self.build(resort_id:, season:)
    {
      title: "Parking Information",
      summary_markdown: "",
      types: [],
      rules: [],
      operations: {},
      accessibility: {},
      overnight: {},
      highway_parking: {},
      faqs: [],
      sources: [
        { kind: "manual", name: "#{resort_id.capitalize} Parking Page", url: "", copyright_ok_to_cache: false }
      ],
      media: { cameras: [] },
      notes: "Seeded #{season}. Update as needed."
    }
  end
end
