# app.rb
require 'sinatra'
require 'sinatra/reloader' if development?
require 'fileutils'
require 'securerandom'
require 'combine_pdf'
require 'mini_magick'

# Configuration
set :port, 4567
set :bind, '0.0.0.0'
set :public_folder, File.dirname(__FILE__) + '/public'
set :views, File.dirname(__FILE__) + '/views'
enable :sessions

# Create necessary directories
FileUtils.mkdir_p('public/uploads')
FileUtils.mkdir_p('public/processed')

# Routes
get '/' do
  erb :index
end

# Upload a PDF file
post '/upload' do
  if params[:file] && params[:file][:tempfile]
    @filename = SecureRandom.uuid + '.pdf'
    file_path = "public/uploads/#{@filename}"

    # Save the uploaded file
    File.open(file_path, 'wb') do |f|
      f.write(params[:file][:tempfile].read)
    end

    session[:current_pdf] = @filename
    redirect '/edit'
  else
    @error = "No file uploaded"
    erb :index
  end
end

# Edit PDF page
get '/edit' do
  @filename = session[:current_pdf]
  if @filename.nil?
    redirect '/'
  end

  begin
    # Always reload the PDF to get the current page count
    pdf_path = "public/uploads/#{@filename}"
    if File.exist?(pdf_path)
      pdf = CombinePDF.load(pdf_path)
      @page_count = pdf.pages.length
      puts "Loaded PDF: #{@filename} with #{@page_count} pages"
    else
      @error = "PDF file not found: #{pdf_path}"
      @page_count = 0
    end
  rescue => e
    @error = "Error loading PDF: #{e.message}"
    @page_count = 0
  end

  erb :edit
end

# Remove pages from PDF
post '/remove_pages' do
  filename = session[:current_pdf]
  pages_to_remove = params[:pages].split(',').map(&:strip).map(&:to_i)

  if filename.nil? || pages_to_remove.empty?
    redirect '/edit'
  end

  begin
    # Print debugging info
    puts "Attempting to remove pages: #{pages_to_remove.inspect} from file: #{filename}"

    # Load the PDF
    pdf = CombinePDF.load("public/uploads/#{filename}")
    original_page_count = pdf.pages.length
    puts "Original PDF has #{original_page_count} pages"

    # Create a new PDF with only the pages we want to keep
    new_pdf = CombinePDF.new

    pdf.pages.each_with_index do |page, idx|
      page_num = idx + 1  # Convert to 1-based indexing for comparison
      unless pages_to_remove.include?(page_num)
        new_pdf << page
      end
    end

    puts "New PDF has #{new_pdf.pages.length} pages"

    # Save the modified PDF
    new_pdf.save("public/processed/#{filename}")
    FileUtils.mv("public/processed/#{filename}", "public/uploads/#{filename}")

    # Redirect with success message
    session[:message] = "Successfully removed #{pages_to_remove.length} page(s). Original: #{original_page_count} pages, New: #{new_pdf.pages.length} pages"
    redirect '/edit'
  rescue => e
    @error = "Error removing pages: #{e.message}"
    erb :edit
  end
end

# Add pages to PDF
post '/add_pages' do
  current_filename = session[:current_pdf]

  if current_filename.nil? || !params[:file] || !params[:file][:tempfile]
    redirect '/edit'
  end

  begin
    # Load the current PDF
    current_pdf = CombinePDF.load("public/uploads/#{current_filename}")

    # Load the PDF to add
    new_pdf_path = params[:file][:tempfile].path
    new_pdf = CombinePDF.load(new_pdf_path)

    # Position to add (beginning, end, or specific position)
    position = params[:position]

    if position == 'beginning'
      # Add at the beginning
      new_pdf << current_pdf
      combined_pdf = new_pdf
    elsif position == 'specific' && params[:page_number].to_i > 0
      # Add at a specific position
      page_num = params[:page_number].to_i - 1 # Convert to 0-based index

      # Split the current PDF at the specified position
      first_part = CombinePDF.new
      second_part = CombinePDF.new

      current_pdf.pages.each_with_index do |page, idx|
        if idx < page_num
          first_part << page
        else
          second_part << page
        end
      end

      # Combine the parts with the new PDF in the middle
      combined_pdf = first_part
      combined_pdf << new_pdf
      combined_pdf << second_part
    else
      # Default: Add at the end
      current_pdf << new_pdf
      combined_pdf = current_pdf
    end

    # Save the combined PDF
    combined_pdf.save("public/processed/#{current_filename}")
    FileUtils.mv("public/processed/#{current_filename}", "public/uploads/#{current_filename}")

    redirect '/edit'
  rescue => e
    @error = "Error adding pages: #{e.message}"
    erb :edit
  end
end

# Convert PDF to JPG
post '/pdf_to_jpg' do
  filename = session[:current_pdf]

  if filename.nil?
    redirect '/edit'
  end

  begin
    # Create a unique folder for the JPG images
    jpg_folder = SecureRandom.uuid
    FileUtils.mkdir_p("public/processed/#{jpg_folder}")

    # Convert PDF to JPG images using MiniMagick
    pdf = MiniMagick::Image.open("public/uploads/#{filename}")

    # Determine the number of pages
    page_count = pdf.pages.length

    # Convert each page to JPG
    page_count.times do |i|
      # Extract a specific page
      MiniMagick::Tool::Convert.new do |convert|
        convert << "public/uploads/#{filename}[#{i}]"
        convert << "-quality" << "90"
        convert << "public/processed/#{jpg_folder}/page_#{i+1}.jpg"
      end
    end

    # Save the folder name to the session for download
    session[:jpg_folder] = jpg_folder

    # Create a zip file containing all JPGs
    `zip -j public/processed/#{jpg_folder}.zip public/processed/#{jpg_folder}/*`

    session[:jpg_zip] = "#{jpg_folder}.zip"

    redirect '/download_jpg'
  rescue => e
    @error = "Error converting PDF to JPG: #{e.message}"
    erb :edit
  end
end

# Download JPG images
get '/download_jpg' do
  zip_file = session[:jpg_zip]

  if zip_file.nil?
    redirect '/edit'
  end

  # Provide the zip file for download
  send_file "public/processed/#{zip_file}",
            type: 'application/zip',
            disposition: 'attachment',
            filename: 'pdf_images.zip'
end

# Convert JPG to PDF
post '/jpg_to_pdf' do
  if !params[:files] || params[:files].empty?
    redirect '/edit'
  end

  begin
    # Create a new PDF
    combined_pdf = CombinePDF.new

    # Process each uploaded JPG
    params[:files].each do |file|
      # Convert JPG to PDF using MiniMagick
      jpg_path = file[:tempfile].path
      pdf_path = "public/processed/temp_#{SecureRandom.uuid}.pdf"

      MiniMagick::Tool::Convert.new do |convert|
        convert << jpg_path
        convert << "-quality" << "90"
        convert << pdf_path
      end

      # Add the temporary PDF to the combined PDF
      temp_pdf = CombinePDF.load(pdf_path)
      combined_pdf << temp_pdf

      # Remove the temporary PDF
      FileUtils.rm(pdf_path)
    end

    # Generate a new filename
    new_filename = SecureRandom.uuid + '.pdf'

    # Save the combined PDF
    combined_pdf.save("public/processed/#{new_filename}")

    # Update the session variable
    session[:current_pdf] = new_filename
    FileUtils.mv("public/processed/#{new_filename}", "public/uploads/#{new_filename}")

    redirect '/edit'
  rescue => e
    @error = "Error converting JPG to PDF: #{e.message}"
    erb :edit
  end
end

# Split PDF by file size
post '/split_pdf' do
  filename = session[:current_pdf]
  max_size_mb = params[:max_size_mb].to_f

  if filename.nil? || max_size_mb <= 0
    redirect '/edit'
  end

  begin
    max_bytes = (max_size_mb * 1024 * 1024).to_i
    pdf = CombinePDF.load("public/uploads/#{filename}")
    pages = pdf.pages

    if pages.empty?
      session[:message] = "PDF has no pages to split."
      redirect '/edit'
    end

    chunks = []
    current_chunk = CombinePDF.new
    current_chunk_page_count = 0

    pages.each do |page|
      # Try adding this page to the current chunk
      test_chunk = CombinePDF.new
      # Re-add existing pages from current chunk
      current_chunk.pages.each { |p| test_chunk << p }
      test_chunk << page

      if current_chunk_page_count > 0 && test_chunk.to_pdf.bytesize > max_bytes
        # Current chunk is full, save it and start a new one
        chunks << current_chunk
        current_chunk = CombinePDF.new
        current_chunk << page
        current_chunk_page_count = 1
      else
        current_chunk << page
        current_chunk_page_count += 1
      end
    end

    # Don't forget the last chunk
    chunks << current_chunk if current_chunk_page_count > 0

    # Save chunks to disk
    split_folder = SecureRandom.uuid
    FileUtils.mkdir_p("public/processed/#{split_folder}")

    chunks.each_with_index do |chunk, idx|
      chunk.save("public/processed/#{split_folder}/chunk_#{idx + 1}.pdf")
    end

    # Zip the chunks
    `zip -j public/processed/#{split_folder}.zip public/processed/#{split_folder}/*`

    session[:split_zip] = "#{split_folder}.zip"
    session[:message] = "PDF split into #{chunks.length} chunk(s)."
    redirect '/download_split'
  rescue => e
    @error = "Error splitting PDF: #{e.message}"
    erb :edit
  end
end

# Download split PDF zip
get '/download_split' do
  zip_file = session[:split_zip]

  if zip_file.nil?
    redirect '/edit'
  end

  send_file "public/processed/#{zip_file}",
            type: 'application/zip',
            disposition: 'attachment',
            filename: 'split_pdf.zip'
end

# Download the edited PDF
get '/download' do
  filename = session[:current_pdf]

  if filename.nil?
    redirect '/'
  end

  send_file "public/uploads/#{filename}",
            type: 'application/pdf',
            disposition: 'attachment',
            filename: 'processed.pdf'
end