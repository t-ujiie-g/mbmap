// GSI vector tile layers (国土地理院ベクトルタイル提供実験), as bench/pages/basic/style.json
// draws them (but dashed boundaries): fill, line, circle and horizontal and vertical labels.
export const GSI_LAYERS = [
  {
    "id": "waterarea",
    "type": "fill",
    "source": "gsi",
    "source-layer": "waterarea",
    "paint": {
      "fill-color": "#a8d4f0"
    }
  },
  {
    "id": "structurea",
    "type": "fill",
    "source": "gsi",
    "source-layer": "structurea",
    "paint": {
      "fill-color": "#e0dcd2"
    }
  },
  {
    "id": "building",
    "type": "fill",
    "source": "gsi",
    "source-layer": "building",
    "filter": [
      "==",
      [
        "geometry-type"
      ],
      "Polygon"
    ],
    "paint": {
      "fill-color": [
        "match",
        [
          "get",
          "ftCode"
        ],
        3103,
        "#d9c9b6",
        "#e3ddd3"
      ],
      "fill-opacity": [
        "interpolate",
        [
          "linear"
        ],
        [
          "zoom"
        ],
        14,
        0.7,
        16,
        1
      ]
    }
  },
  {
    "id": "building-outline",
    "type": "line",
    "source": "gsi",
    "source-layer": "building",
    "filter": [
      "==",
      [
        "geometry-type"
      ],
      "LineString"
    ],
    "paint": {
      "line-color": "#c9c0b3",
      "line-width": 0.5
    }
  },
  {
    "id": "contour",
    "type": "line",
    "source": "gsi",
    "source-layer": "contour",
    "paint": {
      "line-color": "#d8c8a8",
      "line-width": 0.5
    }
  },
  {
    "id": "river",
    "type": "line",
    "source": "gsi",
    "source-layer": "river",
    "paint": {
      "line-color": "#7fb8e0",
      "line-width": 1.5
    }
  },
  {
    "id": "road-casing",
    "type": "line",
    "source": "gsi",
    "source-layer": "road",
    "filter": [
      "any",
      [
        "==",
        [
          "get",
          "rdCtg"
        ],
        0
      ],
      [
        "==",
        [
          "get",
          "rdCtg"
        ],
        1
      ]
    ],
    "layout": {
      "line-join": "round",
      "line-cap": "round"
    },
    "paint": {
      "line-color": "#b8a890",
      "line-width": [
        "interpolate",
        [
          "exponential",
          2
        ],
        [
          "zoom"
        ],
        14,
        5,
        18,
        40
      ]
    }
  },
  {
    "id": "road",
    "type": "line",
    "source": "gsi",
    "source-layer": "road",
    "layout": {
      "line-join": "round",
      "line-cap": "round"
    },
    "paint": {
      "line-color": [
        "match",
        [
          "get",
          "rdCtg"
        ],
        0,
        "#f6b26b",
        1,
        "#ffe08a",
        "#ffffff"
      ],
      "line-width": [
        "interpolate",
        [
          "exponential",
          2
        ],
        [
          "zoom"
        ],
        14,
        [
          "match",
          [
            "get",
            "rdCtg"
          ],
          [
            0,
            1
          ],
          3,
          2,
          1,
          1.5
        ],
        18,
        [
          "match",
          [
            "get",
            "rdCtg"
          ],
          [
            0,
            1
          ],
          32,
          2,
          16,
          20
        ]
      ]
    }
  },
  {
    "id": "railway",
    "type": "line",
    "source": "gsi",
    "source-layer": "railway",
    "filter": [
      "in",
      [
        "get",
        "snglDbl"
      ],
      [
        "literal",
        [
          1,
          2,
          3,
          4
        ]
      ]
    ],
    "paint": {
      "line-color": "#6d6d6d",
      "line-width": [
        "step",
        [
          "zoom"
        ],
        1.5,
        16,
        3
      ]
    }
  },
  {
    "id": "boundary",
    "type": "line",
    "source": "gsi",
    "source-layer": "boundary",
    "paint": {
      "line-color": "#a07ab0",
      "line-width": 1,
      "line-dasharray": [4, 2]
    }
  },
  {
    "id": "elevation",
    "type": "circle",
    "source": "gsi",
    "source-layer": "elevation",
    "paint": {
      "circle-radius": 2.5,
      "circle-color": "#8c6d31"
    }
  },
  {
    "id": "symbol",
    "type": "circle",
    "source": "gsi",
    "source-layer": "symbol",
    "paint": {
      "circle-radius": [
        "interpolate",
        [
          "linear"
        ],
        [
          "zoom"
        ],
        14,
        3,
        18,
        7
      ],
      "circle-color": [
        "match",
        [
          "get",
          "ftCode"
        ],
        [
          3216,
          3242
        ],
        "#d6604d",
        [
          6311,
          6312,
          6321,
          6341
        ],
        "#4393c3",
        "#7f7f7f"
      ],
      "circle-stroke-width": 1,
      "circle-stroke-color": "#ffffff"
    }
  },
  {
    "id": "label",
    "type": "symbol",
    "source": "gsi",
    "source-layer": "label",
    "filter": [
      "!",
      [
        "in",
        [
          "get",
          "arrng"
        ],
        [
          "literal",
          [
            2,
            4
          ]
        ]
      ]
    ],
    "layout": {
      "text-field": "{knj}",
      "text-size": 12,
      "text-max-width": 8,
      "symbol-sort-key": [
        "get",
        "annoCtg"
      ]
    },
    "paint": {
      "text-color": "#333333",
      "text-halo-color": "#ffffff",
      "text-halo-width": 1.5
    }
  },
  {
    "id": "label-vertical",
    "type": "symbol",
    "source": "gsi",
    "source-layer": "label",
    "filter": [
      "in",
      [
        "get",
        "arrng"
      ],
      [
        "literal",
        [
          2,
          4
        ]
      ]
    ],
    "layout": {
      "text-field": "{knj}",
      "text-size": 12,
      "text-max-width": 8,
      "text-writing-mode": [
        "vertical"
      ],
      "symbol-sort-key": [
        "get",
        "annoCtg"
      ]
    },
    "paint": {
      "text-color": "#333333",
      "text-halo-color": "#ffffff",
      "text-halo-width": 1.5
    }
  }
];
