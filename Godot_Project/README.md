# LGA Airspace Visualization

This Godot project visualizes the FAA's Low Altitude Authorization and Notification Capability (LAANC) data for the LaGuardia Airport (LGA) region. The visualization displays drone flight restrictions in a grid format similar to the FAA's official airspace map.

## Features

- Visual grid-based display of drone altitude restrictions in the LGA area
- Color-coded cells based on the maximum allowable altitude:
  - Red (0 ft): No drone flights allowed
  - Orange (50 ft): Very low altitude restrictions
  - Yellow (100 ft): Low altitude restrictions
  - Light Green (200 ft): Medium altitude restrictions
  - Blue-Green (300 ft): High altitude restrictions
  - Green (400 ft): Maximum allowable altitude
- Interactive navigation:
  - Zoom in/out with mouse wheel or buttons
  - Pan by middle-mouse dragging
  - Reset view button
- Altitude values displayed within each grid cell

## Data Source

The visualization uses data from the FAA's UAS Facility Maps, which indicate the maximum altitudes where the FAA may authorize Part 107 drone operations in controlled airspace. This data is stored in `Data/filtered_data_LGA.csv` with the following format:

- CEILING: Maximum allowable drone altitude in feet (0 = no flight allowed)
- LATITUDE: Geographic coordinate (north-south position)
- LONGITUDE: Geographic coordinate (east-west position)

## How to Use

1. Load the project in Godot (v4.0+)
2. Run the project
3. Navigate using:
   - Mouse wheel to zoom in/out
   - Middle-mouse button to pan the view
   - Reset button to restore the default view

## Implementation Details

- The visualization uses Godot's 2D drawing capabilities to render the grid cells
- Each grid cell represents a specific geographic location with a maximum altitude
- The data is read from a CSV file and displayed according to its latitude/longitude coordinates

## Purpose

This visualization helps drone pilots understand where and at what altitudes they may fly in the controlled airspace around LaGuardia Airport. It serves as a visual reference for planning flights in compliance with FAA regulations. 