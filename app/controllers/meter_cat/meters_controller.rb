module MeterCat

  class MetersController < ApplicationController

    DEFAULT_DAYS = 7

    def index
      if date = params[ :date ]
        @date = Date.civil( date[ :year ].to_i, date[ :month ].to_i, date[ :day ].to_i )
      end
      @days = params[ :days ].to_i if params[ :days ]
      @names = params[ :names ].map { |name| name.to_sym } if params[ :names ]

      @all_names = MeterCat.names
      @date ||= Date.today
      @days ||= DEFAULT_DAYS

      @range = (@date - @days) .. @date
      @meters = Meter.to_h( @range, @names )

      respond_to do |format|
        format.html do
          MeterCat.add( :meter_cat_html )
        end
        format.csv do
          MeterCat.add( :meter_cat_csv )
          render :text => Meter.to_csv( @range, @names ), :content_type => 'text/csv'
        end
      end
    end

  end

end