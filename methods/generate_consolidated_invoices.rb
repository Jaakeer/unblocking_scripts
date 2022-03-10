def generate_consolidated_invoices(company_id)
  selected_date = calculate_date(invoice_generation_day)
    if selected_date.last.true?
      payload = {
          company_id: company_id, #company_id
          invoice_date: "Tue, 17 Mar 2020 05:46:41 +0530", #Invoice Date
          invoice_generation_day: 15, #Generation Cycle
          send_mail: false, #If you want to notify client
          end_date: "2020-03-18 23:59:59"
      }
      job_response = GenerateConsolidatedInvoiceJob.perform_now(company_id,payload.as_json)
      if job_response.present?
        BizongoNotifier.alert(Exception.new(job_response.join(",")), {params: {company_id: company_id, payload:payload.as_json} })
      end
    end
  end
end

def calculate_date(day)
  today = DateTime.now
  invoice_generation_date = today - 1.days
  month_day = invoice_generation_date.strftime('%d').to_i
  end_of_month_day = invoice_generation_date.end_of_month.strftime('%d').to_i
  take_action = false
  if (end_of_month_day - month_day) >= day && (month_day% day).zero?
    take_action = true
  end

  [invoice_generation_date, take_action]
end
