require 'spec_helper'

include MeterCat

describe MeterCat::Meter do

  before( :each ) do
    Kernel.stub( :sleep )

    @meter = Meter.new( :name => 'test', :created_on => '2013-09-04', :value => 727 )
  end

  it 'has valid test data' do
    setup_meters
    Meter.count.should > 0
  end

  describe 'constants' do

    it 'defines a default expiration time' do
      Meter::DEFAULT_EXPIRATION.should be( 3600 )
    end

    it 'defines a default number of retry attempts' do
      Meter::DEFAULT_RETRY_ATTEMPTS.should be( 5 )
    end

    it 'defines a default delay between retries' do
      Meter::DEFAULT_RETRY_DELAY.should be( 1 )
    end

  end

  it 'validates the presence of name' do
    @meter.should be_valid

    @meter.name = nil
    @meter.should be_invalid
    @meter.errors[ :name ].should_not be_empty
  end

  #############################################################################
  # Meter#add

  describe '#add' do

    it 'creates a new record' do
      @meter.add.should be_true

      test = Meter.find_by_name_and_created_on( @meter.name, @meter.created_on )
      test.should be_present
      test.value.should eql( @meter.value )
    end

    it 'increments an existing record' do
      @meter.save.should be_true
      @meter.add.should be_true

      test = Meter.find_by_name_and_created_on( @meter.name, @meter.created_on )
      test.should be_present
      test.value.should eql( @meter.value * 2 )
    end

    it 'returns the result of the save' do
      Meter.should_receive( :find_by_name_and_created_on ).twice.and_return( @meter )

      [ true, false ].each do |boolean|
        @meter.should_receive( :save ).and_return( boolean )
        @meter.add.should eql( boolean )
      end
    end

    it 'does not catch ActiveRecord::StaleObjectError exceptions' do
      @meter.lock_version = 1
      @meter.save.should be_true

      Meter.should_receive( :find_by_name_and_created_on ).and_return( @meter )
      @meter.lock_version = 0
      expect { @meter.add }.to raise_error( ActiveRecord::StaleObjectError )
    end

    it 'does not catch ActiveRecord::RecordNotUnique exceptions' do
      @meter.save.should be_true
      Meter.should_receive( :find_by_name_and_created_on ).and_return( nil )

      expect { @meter.add }.to raise_error( ActiveRecord::RecordNotUnique )
    end

  end

  #############################################################################
  # Meter#add_with_retry

  describe '#add_with_retry' do

    before( :each ) do
      @retry_attempts = MeterCat.config.retry_attempts
    end

    it 'calls #add' do
      @meter.should_receive( :add ).once.and_return( true )
      @meter.add_with_retry.should be_true
    end

    it 'returns true if it succeeds' do
      @meter.add_with_retry.should be_true
    end

    it 'catches ActiveRecord::StaleObjectError exceptions' do
      @meter.should_receive( :add ).exactly( @retry_attempts ).times.and_raise( ActiveRecord::StaleObjectError.new( nil, nil ) )
      @meter.add_with_retry.should be_false
    end

    it 'catches ActiveRecord::RecordNotUnique exceptions' do
      @meter.should_receive( :add ).exactly( @retry_attempts ).times.and_raise( ActiveRecord::RecordNotUnique.new( nil, nil ) )
      @meter.add_with_retry.should be_false
    end

    it 'retries up to Meter::MAX_ADD_ATTEMPTS times' do
      @meter.should_receive( :add ).exactly( @retry_attempts ).times.and_return( false )
      @meter.add_with_retry.should be_false
    end

    it 'sleeps on each retry' do
      Kernel.should_receive( :sleep ).exactly( @retry_attempts ).times
      @meter.should_receive( :add ).exactly( @retry_attempts ).times.and_return( false )
      @meter.add_with_retry.should be_false
    end

    it 'returns false if it fails' do
      @meter.should_receive( :add ).exactly( @retry_attempts ).times.and_return( false )
      @meter.add_with_retry.should be_false
    end

    it 'succeeds if a retry works' do
      @meter.should_receive( :add ).twice.and_return( false, true )
      @meter.add_with_retry.should be_true
    end

  end

  #############################################################################
  # Meter#expired?

  describe '#expired?' do

    before( :each ) do
      @expiration = MeterCat.config.expiration
      @now = Time.now
      Time.should_receive( :now ).and_return( @now )
    end

    it 'returns false if age is less than expiration' do
      @meter.created_at = @now + @expiration
      @meter.expired?.should be_false
    end

    it 'returns true if age is older than expiration' do
      @meter.created_at = @now - @expiration * 2
      @meter.expired?.should be_true
    end

  end

  #############################################################################
  # Meter::names

  describe '::names' do

    it 'returns all distinct meter names from the db' do
      expected = Meter.uniq.pluck( :name ).sort.map { |name| name.to_sym }
      Meter.names.should eql( expected )
    end

  end

  #############################################################################
  # Meter::random

  describe '::random' do

    before( :each ) do
      @args = {
          :name => 'test',
          :min => '1',
          :max => '10',
          :days => '365'
      }

      @name = @args[ :name ]
      @min = @args[ :min ].to_i
      @max = @args[ :max ].to_i
      @days = @args[ :days ]
    end

    it 'creates meters within the given name and date range' do
      Meter.delete_all
      Meter.random( @args )
      Meter.count.should eql( @days.to_i + 1 )

      Meter.all.each do |meter|
        meter.value.should >= @min
        meter.value.should <= @max
      end
    end

    it 'fails silently if the meter already exists' do
      Meter.random( @args )
      Meter.random( @args )
    end

  end

  #############################################################################
  # Meter::set

  describe '::set' do

    it 'creates a new record' do
      Meter.set( @meter.name, @meter.value, @meter.created_on).should be_true

      test = Meter.find_by_name_and_created_on( @meter.name, @meter.created_on )
      test.should be_present
      test.value.should eql( @meter.value )
    end

    it 'updates an existing record' do
      @meter.save.should be_true
      Meter.set( @meter.name, @meter.value - 1, @meter.created_on).should be_true

      test = Meter.find_by_name_and_created_on( @meter.name, @meter.created_on )
      test.should be_present
      test.value.should eql( @meter.value - 1 )
    end

    it 'returns the result of the save' do
      Meter.should_receive( :find_by_name_and_created_on ).twice.and_return( @meter )

      [ true, false ].each do |boolean|
        @meter.should_receive( :save ).and_return( boolean )
        Meter.set( @meter.name, @meter.value - 1, @meter.created_on).should eql( boolean )
      end
    end
  end

  #############################################################################
  # Meter::to_h

  describe '::to_h' do

    before( :each ) do
      setup_meters
      @to_h = Meter.to_h( @range, @names )
    end

    it 'finds all meters in the given range' do
      Meter.where( @conditions ) do |expected|
        @to_h[ expected.name ][ expected.created_on ].should be_present
      end
    end

    it 'returns a hash of name to date to value' do
      Meter.where( @conditions  ) do |expected|
        @to_h[ expected.name ][ expected.created_on ].should eql( expected.value )
      end
    end

    it 'filters by name' do
      @to_h.should have_key( @user_created_1.name.to_sym )
      @to_h.should_not have_key( @login_failed_3.name.to_sym )
    end

    it 'injects dependencies into the names array' do
      MeterCat.config.calculator.should_receive( :dependencies ).with( @names )
      @to_h = Meter.to_h( @range, @names )
    end


    it 'adds calculated values to the results' do
      MeterCat.config.calculator.should_receive( :calculate ).with( kind_of( Hash ), @range, @names )
      @to_h = Meter.to_h( @range, @names )
    end

    it 'tolerates a nil names array' do
      @to_h = Meter.to_h( @range, @names )
    end

    it 'works with large batches of data' do
      days = 2000
      today = Date.today
      Meter.random( :name => :test, :min => 0, :max => 100, :days => days )
      @to_h = Meter.to_h(( today - days ) .. today )
      @range
    end

  end

  #############################################################################
  # Meter::to_csv

  describe '::to_csv' do

    before( :each ) do
      setup_meters
      @to_csv = Meter.to_csv( @range, @names )
      @csv = CSV.parse( @to_csv )
    end

    it 'generates a CSV file' do
      @to_csv.should eql_file( 'spec/data/meters.csv' )
    end

    it 'includes a header row' do
      expected = [ nil ] + Meter.to_h( @range, @names ).keys.sort!.map { |name| name.to_s }
      @csv[ 0 ].should eql( expected )
    end

    it 'includes a row for each meter' do
      @csv.size.should eql( Meter.where( @conditions ).count + 1 )
    end

  end

end

